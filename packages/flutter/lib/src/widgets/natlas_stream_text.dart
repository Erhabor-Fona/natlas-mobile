import 'package:flutter/material.dart';

import '../models/chat_response.dart';

/// Renders a streaming chat reply as it arrives, with a blinking cursor
/// while the stream is still open.
///
/// ```dart
/// NAtlasStreamText(
///   stream: client.chatStream(
///     messages: [ChatMessage.user('Sannu!')],
///     language: NAtlasLanguage.hausa,
///   ),
///   style: Theme.of(context).textTheme.bodyLarge,
/// )
/// ```
class NAtlasStreamText extends StatefulWidget {
  /// The chunk stream from [NAtlasClient.chatStream].
  final Stream<ChatStreamChunk> stream;

  /// Text style for the streamed reply. Falls back to the ambient
  /// [DefaultTextStyle] when null.
  final TextStyle? style;

  /// Show a blinking cursor while streaming.
  final bool showCursor;

  /// Called once with the complete text when the stream closes.
  final void Function(String fullText)? onComplete;

  /// Called if the stream emits an error.
  final void Function(Object error)? onError;

  /// Creates a widget that renders [stream] as it arrives.
  ///
  /// Subscribes in `initState`, so give it a [Key] tied to the message being
  /// streamed — otherwise a rebuild with a new stream will not resubscribe.
  const NAtlasStreamText({
    super.key,
    required this.stream,
    this.style,
    this.showCursor = true,
    this.onComplete,
    this.onError,
  });

  @override
  State<NAtlasStreamText> createState() => _NAtlasStreamTextState();
}

class _NAtlasStreamTextState extends State<NAtlasStreamText> {
  final StringBuffer _buffer = StringBuffer();
  bool _done = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    widget.stream.listen(
      (chunk) {
        if (!mounted) return;
        setState(() => _buffer.write(chunk.delta));
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _done = true);
        widget.onComplete?.call(_buffer.toString());
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _error = e;
          _done = true;
        });
        widget.onError?.call(e);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _buffer.isEmpty) {
      return Text(
        'Error: $_error',
        style: (widget.style ?? const TextStyle())
            .copyWith(color: Theme.of(context).colorScheme.error),
      );
    }

    final text = _buffer.toString();
    final showCursor = widget.showCursor && !_done;

    return RichText(
      text: TextSpan(
        style: widget.style ?? DefaultTextStyle.of(context).style,
        children: [
          TextSpan(text: text),
          if (showCursor)
            const WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: _BlinkingCursor(),
            ),
        ],
      ),
    );
  }
}

class _BlinkingCursor extends StatefulWidget {
  const _BlinkingCursor();

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 2,
        height: 16,
        margin: const EdgeInsets.only(left: 2),
        color: DefaultTextStyle.of(context).style.color ??
            Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}
