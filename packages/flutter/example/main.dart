// A minimal single-file example: pick a language, type with the diacritic
// bar, and watch N-ATLaS reply token by token.
//
// Point it at your own gateway — see docs/self-hosting.md in the repo.
// Run with:
//
//     flutter run -t example/main.dart \
//       --dart-define=NATLAS_URL=https://your-gateway.modal.run \
//       --dart-define=NATLAS_KEY=your_api_key

import 'package:flutter/material.dart';
import 'package:natlas_flutter/natlas_flutter.dart';

/// Gateway base URL, supplied with `--dart-define=NATLAS_URL=...`.
const String gatewayUrl = String.fromEnvironment(
  'NATLAS_URL',
  defaultValue: 'https://your-gateway.modal.run',
);

/// Gateway API key, supplied with `--dart-define=NATLAS_KEY=...`.
const String gatewayKey = String.fromEnvironment(
  'NATLAS_KEY',
  defaultValue: 'your_api_key',
);

void main() => runApp(const ExampleApp());

/// Root of the example app.
class ExampleApp extends StatelessWidget {
  /// Creates the example app.
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'N-ATLaS example',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF008751),
        useMaterial3: true,
      ),
      home: const ChatPage(),
    );
  }
}

/// A single-turn chat screen.
class ChatPage extends StatefulWidget {
  /// Creates the chat screen.
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final NAtlasClient _client = NAtlasClient(
    baseUrl: gatewayUrl,
    apiKey: gatewayKey,
  );
  final TextEditingController _input = TextEditingController();

  NAtlasLanguage _language = NAtlasLanguage.yoruba;
  Stream<ChatStreamChunk>? _reply;

  @override
  void dispose() {
    _input.dispose();
    _client.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;

    setState(() {
      // A new stream needs a new subscription, so NAtlasStreamText is keyed
      // on the prompt below.
      _reply = _client.chatStream(
        messages: [ChatMessage.user(text)],
        language: _language,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final reply = _reply;

    return Scaffold(
      appBar: AppBar(
        title: const Text('N-ATLaS'),
        actions: [
          DropdownButton<NAtlasLanguage>(
            value: _language,
            underline: const SizedBox.shrink(),
            onChanged: (lang) {
              if (lang == null) return;
              // Switching language starts a fresh turn: the model would
              // otherwise keep answering in the previous one.
              setState(() {
                _language = lang;
                _reply = null;
              });
            },
            items: [
              for (final lang in NAtlasLanguage.values)
                DropdownMenuItem<NAtlasLanguage>(
                  value: lang,
                  child: Text(lang.displayName),
                ),
            ],
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: reply == null
                  ? Center(
                      child: Text(
                        'Ask something in ${_language.displayName}.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : SingleChildScrollView(
                      child: NAtlasStreamText(
                        key: ValueKey(reply),
                        stream: reply,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
            ),
          ),
          // Tone and dot-below keys for the selected language. Renders
          // nothing for Nigerian English.
          NAtlasDiacriticBar(
            controller: _input,
            language: _language,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Type a message',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
