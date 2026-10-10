import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:natlas_flutter/natlas_flutter.dart';

import '../services/audio_recorder.dart';
import '../services/settings_store.dart';
import '../widgets/language_picker.dart';
import '../widgets/message_bubble.dart';
import 'settings_screen.dart';

/// A turn in the demo conversation.
class _Turn {
  final bool isUser;
  final String text;

  /// Set when this turn came from speech, so the UI can show a mic badge.
  final double? spokenSeconds;

  /// True while the assistant reply is still streaming in.
  final bool streaming;

  const _Turn({
    required this.isUser,
    required this.text,
    this.spokenSeconds,
    this.streaming = false,
  });

  _Turn copyWith({String? text, bool? streaming}) => _Turn(
        isUser: isUser,
        text: text ?? this.text,
        spokenSeconds: spokenSeconds,
        streaming: streaming ?? this.streaming,
      );
}

class ChatScreen extends StatefulWidget {
  final SettingsStore settings;

  const ChatScreen({super.key, required this.settings});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late NAtlasClient _client;
  final AudioRecorderService _recorder = AudioRecorderService();
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  final List<_Turn> _turns = [];
  bool _recording = false;
  bool _busy = false;
  String? _banner;

  @override
  void initState() {
    super.initState();
    _client = widget.settings.buildClient();
    _checkGateway();
  }

  @override
  void dispose() {
    _client.dispose();
    _recorder.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  NAtlasLanguage get _language => widget.settings.language;

  // ── Gateway health ────────────────────────────────────────────────────────

  Future<void> _checkGateway() async {
    try {
      await _client.health();
      if (mounted) setState(() => _banner = null);
    } on NAtlasException catch (e) {
      if (mounted) {
        setState(() => _banner = 'Gateway unreachable: ${e.message}');
      }
    } catch (e) {
      if (mounted) setState(() => _banner = 'Gateway unreachable: $e');
    }
  }

  // ── Conversation history for the model ────────────────────────────────────

  List<ChatMessage> _history() => _turns
      .where((t) => !t.streaming && t.text.isNotEmpty)
      .map((t) =>
          t.isUser ? ChatMessage.user(t.text) : ChatMessage.assistant(t.text))
      .toList();

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  // ── Text send ─────────────────────────────────────────────────────────────

  Future<void> _sendText() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;

    _input.clear();
    final history = _history();

    setState(() {
      _turns.add(_Turn(isUser: true, text: text));
      _turns.add(const _Turn(isUser: false, text: '', streaming: true));
      _busy = true;
    });
    _scrollToBottom();

    await _streamReply([...history, ChatMessage.user(text)]);
  }

  // ── Voice send ────────────────────────────────────────────────────────────

  Future<void> _toggleRecording() async {
    if (_busy) return;

    if (!_recording) {
      try {
        await _recorder.start();
        setState(() => _recording = true);
      } on StateError catch (e) {
        _showSnack(e.message);
      }
      return;
    }

    setState(() {
      _recording = false;
      _busy = true;
    });

    // stop() throws a StateError naming the step that failed, which is far
    // more useful than a blanket "Nothing recorded".
    final Uint8List audio;
    try {
      audio = await _recorder.stop();
    } on StateError catch (e) {
      setState(() => _busy = false);
      _showSnack(e.message);
      return;
    }

    // Transcribe first so the user sees what was heard before the reply starts.
    TranscriptionResult transcription;
    try {
      debugPrint('[natlas] uploading ${audio.length} bytes '
          'as recording.${AudioRecorderService.fileExtension}');
      transcription = await _client.transcribe(
        audio: audio,
        language: _language,
        filename: 'recording.${AudioRecorderService.fileExtension}',
      );
    } on NAtlasException catch (e) {
      setState(() => _busy = false);
      // e.detail carries the gateway's explanation — for a 422 that is the
      // tail of ffmpeg's stderr, which is the only thing that says WHY the
      // conversion failed. Showing only e.message hides it.
      debugPrint('[natlas] transcription failed: $e');
      _showSnack(
        '${e.message}: ${(e.detail ?? '').trim()}',
        duration: const Duration(seconds: 10),
      );
      return;
    }

    if (transcription.text.trim().isEmpty) {
      setState(() => _busy = false);
      _showSnack('Could not make out any speech');
      return;
    }

    final history = _history();

    setState(() {
      _turns.add(_Turn(
        isUser: true,
        text: transcription.text,
        spokenSeconds: transcription.durationSeconds,
      ));
      _turns.add(const _Turn(isUser: false, text: '', streaming: true));
    });
    _scrollToBottom();

    await _streamReply([...history, ChatMessage.user(transcription.text)]);
  }

  // ── Streaming the reply ───────────────────────────────────────────────────

  Future<void> _streamReply(List<ChatMessage> messages) async {
    final buffer = StringBuffer();

    try {
      await for (final chunk in _client.chatStream(
        messages: messages,
        language: _language,
        maxTokens: 512,
      )) {
        buffer.write(chunk.delta);
        if (!mounted) return;
        setState(() {
          _turns[_turns.length - 1] =
              _turns.last.copyWith(text: buffer.toString());
        });
        _scrollToBottom();
      }

      if (!mounted) return;
      setState(() {
        _turns[_turns.length - 1] = _turns.last.copyWith(streaming: false);
        _busy = false;
      });
    } on NAtlasException catch (e) {
      if (!mounted) return;
      setState(() {
        // Drop the empty placeholder turn.
        if (_turns.isNotEmpty && _turns.last.text.isEmpty) _turns.removeLast();
        _busy = false;
      });
      _showSnack('${e.message}${e.statusCode == 401 ? "" : " — try again"}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_turns.isNotEmpty && _turns.last.text.isEmpty) _turns.removeLast();
        _busy = false;
      });
      _showSnack('$e');
    }
  }

  void _showSnack(String message, {Duration? duration}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration ?? const Duration(seconds: 4),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('N-ATLaS'),
        actions: [
          LanguagePicker(
            value: _language,
            onChanged: (lang) async {
              if (lang == _language) return;
              final hadConversation = _turns.isNotEmpty;

              // Resolve the messenger BEFORE the await. Looking it up from
              // `context` afterwards is a use across an async gap, and the
              // State's `mounted` flag does not guard it — `context` here is
              // build()'s parameter, which shadows State.context.
              final messenger = ScaffoldMessenger.of(context);

              // The conversation history is sent with every request, and the
              // model follows the language it can SEE far more strongly than
              // the language named in the system prompt. Carrying ten Yoruba
              // turns into an Igbo request gets you Yoruba back. Each language
              // therefore starts a fresh conversation.
              setState(() {
                widget.settings.language = lang;
                _turns.clear();
              });
              await widget.settings.save();

              if (hadConversation) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      'Switched to ${lang.displayName} — started a new conversation',
                    ),
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SettingsScreen(settings: widget.settings),
              ));
              if (!mounted) return;
              setState(() {
                _client.dispose();
                _client = widget.settings.buildClient();
              });
              await _checkGateway();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_banner != null)
            MaterialBanner(
              content: Text(_banner!),
              leading: const Icon(Icons.cloud_off_outlined),
              actions: [
                TextButton(
                  onPressed: _checkGateway,
                  child: const Text('Retry'),
                ),
              ],
            ),
          Expanded(
            child: _turns.isEmpty
                ? _EmptyState(language: _language)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: _turns.length,
                    itemBuilder: (context, i) {
                      final turn = _turns[i];
                      return MessageBubble(
                        isUser: turn.isUser,
                        text: turn.text,
                        spokenSeconds: turn.spokenSeconds,
                        streaming: turn.streaming,
                      );
                    },
                  ),
          ),
          _Composer(
            controller: _input,
            recording: _recording,
            busy: _busy,
            language: _language,
            onSend: _sendText,
            onMicTap: _toggleRecording,
          ),
        ],
      ),
    );
  }
}

// ── Empty state ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final NAtlasLanguage language;

  const _EmptyState({required this.language});

  String get _greeting => switch (language) {
        NAtlasLanguage.hausa => 'Sannu! Yi magana ko rubuta.',
        NAtlasLanguage.igbo => 'Kedụ! Kwuo okwu ma ọ bụ dee.',
        NAtlasLanguage.yoruba => 'Báwo ni! Sọ̀rọ̀ tàbí kọ.',
        NAtlasLanguage.english => 'Hello! Speak or type to begin.',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.graphic_eq_rounded,
              size: 64,
              color: theme.colorScheme.primary.withAlpha(120),
            ),
            const SizedBox(height: 20),
            Text(
              _greeting,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '${language.displayName} · N-ATLaS',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Composer ────────────────────────────────────────────────────────────────

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool recording;
  final bool busy;
  final NAtlasLanguage language;
  final VoidCallback onSend;
  final VoidCallback onMicTap;

  const _Composer({
    required this.controller,
    required this.recording,
    required this.busy,
    required this.language,
    required this.onSend,
    required this.onMicTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(color: theme.dividerColor.withAlpha(80)),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Phone keyboards cannot type Yoruba or Igbo diacritics, and tone
            // is semantic in both — N-ATLaS answers noticeably better on
            // marked input. Renders nothing for Nigerian English.
            if (!busy && !recording)
              NAtlasDiacriticBar(
                controller: controller,
                language: language,
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: !busy && !recording,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: recording
                      ? 'Recording…'
                      : 'Message in ${language.displayName}',
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _MicButton(
              recording: recording,
              busy: busy,
              onTap: onMicTap,
            ),
            const SizedBox(width: 4),
            IconButton.filled(
              onPressed: busy || recording ? null : onSend,
              icon: const Icon(Icons.send_rounded),
              tooltip: 'Send',
            ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  final bool recording;
  final bool busy;
  final VoidCallback onTap;

  const _MicButton({
    required this.recording,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (busy && !recording) {
      return const SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return IconButton.filled(
      onPressed: onTap,
      tooltip: recording ? 'Stop and send' : 'Hold to speak',
      style: IconButton.styleFrom(
        backgroundColor:
            recording ? theme.colorScheme.error : theme.colorScheme.secondary,
      ),
      icon: Icon(recording ? Icons.stop_rounded : Icons.mic_rounded),
    );
  }
}
