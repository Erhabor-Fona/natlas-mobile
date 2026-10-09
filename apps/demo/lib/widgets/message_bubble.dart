import 'package:flutter/material.dart';

/// One chat turn. User turns sit right and tinted; assistant turns sit left.
class MessageBubble extends StatelessWidget {
  final bool isUser;
  final String text;

  /// When the turn came from speech, the length of the recording in seconds.
  final double? spokenSeconds;

  /// True while the reply is still streaming — shows a typing indicator when
  /// no text has arrived yet, and a cursor once it has.
  final bool streaming;

  const MessageBubble({
    super.key,
    required this.isUser,
    required this.text,
    this.spokenSeconds,
    this.streaming = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final background = isUser ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    final foreground = isUser ? scheme.onPrimaryContainer : scheme.onSurface;

    // Streaming with nothing yet — show the three-dot indicator.
    if (streaming && text.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 4, 48, 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: background,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
          ),
          child: const _TypingDots(),
        ),
      );
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: isUser
            ? const EdgeInsets.fromLTRB(48, 4, 12, 4)
            : const EdgeInsets.fromLTRB(12, 4, 48, 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(isUser ? 18 : 4),
            topRight: Radius.circular(isUser ? 4 : 18),
            bottomLeft: const Radius.circular(18),
            bottomRight: const Radius.circular(18),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (spokenSeconds != null) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.mic_rounded, size: 13, color: foreground.withAlpha(170)),
                  const SizedBox(width: 4),
                  Text(
                    '${spokenSeconds!.toStringAsFixed(1)}s',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: foreground.withAlpha(170)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
            _BubbleText(
              text: text,
              style: theme.textTheme.bodyLarge?.copyWith(color: foreground),
              showCursor: streaming,
            ),
          ],
        ),
      ),
    );
  }
}

class _BubbleText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final bool showCursor;

  const _BubbleText({
    required this.text,
    required this.style,
    required this.showCursor,
  });

  @override
  Widget build(BuildContext context) {
    if (!showCursor) {
      return SelectableText(text, style: style);
    }

    return RichText(
      text: TextSpan(
        style: style,
        children: [
          TextSpan(text: text),
          const WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _Cursor(),
          ),
        ],
      ),
    );
  }
}

class _Cursor extends StatefulWidget {
  const _Cursor();

  @override
  State<_Cursor> createState() => _CursorState();
}

class _CursorState extends State<_Cursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  )..repeat(reverse: true);

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
        height: 15,
        margin: const EdgeInsets.only(left: 2),
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;

    return SizedBox(
      width: 36,
      height: 10,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(3, (i) {
              // Each dot peaks a third of a cycle after the previous one.
              final phase = (_controller.value - i * 0.22) % 1.0;
              final lift = phase < 0.5 ? (0.5 - phase) * 2 : 0.0;
              return Opacity(
                opacity: 0.35 + lift * 0.65,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
