import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../language.dart';

/// A single entry on the [NAtlasDiacriticBar].
class DiacriticKey {
  /// The text inserted at the cursor. For a combining mark this is the bare
  /// combining codepoint, which attaches to whatever precedes the cursor.
  final String insert;

  /// What the key shows. Combining marks are drawn on a dotted circle (◌́)
  /// so they are visible on their own.
  final String label;

  /// Screen-reader description.
  final String semanticLabel;

  /// Creates a key.
  ///
  /// For a plain character [insert] and [label] are the same. For a combining
  /// mark, [insert] is the bare mark and [label] draws it on a dotted circle
  /// (U+25CC) so it is visible without a base letter.
  ///
  /// Deliberately a plain const constructor rather than named factories:
  /// factory constructors can never be const in Dart, which would stop
  /// [kDiacriticKeys] from being a const map.
  const DiacriticKey({
    required this.insert,
    required this.label,
    required this.semanticLabel,
  });
}

/// Per-language key sets.
///
/// Yorùbá and Igbo need a dot-below vowel carrying a tone mark (ẹ́, ị̀). Those
/// combinations have **no precomposed Unicode codepoint** — not even after NFC
/// normalisation — so they are typed as base letter followed by a combining
/// accent. That is why the tone keys are separate from the letter keys.
///
/// Hausa Boko orthography uses hooked consonants and does not mark tone in
/// standard writing, so it gets no accent keys.
const Map<NAtlasLanguage, List<DiacriticKey>> kDiacriticKeys = {
  NAtlasLanguage.yoruba: [
    // Dot-below letters (precomposed).
    DiacriticKey(insert: 'ẹ', label: 'ẹ', semanticLabel: 'e with dot below'),
    DiacriticKey(insert: 'ọ', label: 'ọ', semanticLabel: 'o with dot below'),
    DiacriticKey(insert: 'ṣ', label: 'ṣ', semanticLabel: 's with dot below'),
    // Tone marks — combining, so they attach to the character just typed.
    DiacriticKey(insert: '́', label: '◌́', semanticLabel: 'high tone, acute'),
    DiacriticKey(insert: '̀', label: '◌̀', semanticLabel: 'low tone, grave'),
    // Syllabic nasals (precomposed, common enough to earn a key).
    DiacriticKey(insert: 'ń', label: 'ń', semanticLabel: 'n with acute'),
    DiacriticKey(insert: 'ǹ', label: 'ǹ', semanticLabel: 'n with grave'),
  ],
  NAtlasLanguage.igbo: [
    DiacriticKey(insert: 'ị', label: 'ị', semanticLabel: 'i with dot below'),
    DiacriticKey(insert: 'ọ', label: 'ọ', semanticLabel: 'o with dot below'),
    DiacriticKey(insert: 'ụ', label: 'ụ', semanticLabel: 'u with dot below'),
    DiacriticKey(insert: 'ṅ', label: 'ṅ', semanticLabel: 'n with dot above'),
    DiacriticKey(insert: '́', label: '◌́', semanticLabel: 'high tone, acute'),
    DiacriticKey(insert: '̀', label: '◌̀', semanticLabel: 'low tone, grave'),
  ],
  NAtlasLanguage.hausa: [
    DiacriticKey(insert: 'ɓ', label: 'ɓ', semanticLabel: 'b with hook'),
    DiacriticKey(insert: 'ɗ', label: 'ɗ', semanticLabel: 'd with hook'),
    DiacriticKey(insert: 'ƙ', label: 'ƙ', semanticLabel: 'k with hook'),
    DiacriticKey(insert: 'ƴ', label: 'ƴ', semanticLabel: 'y with hook'),
    DiacriticKey(insert: 'ʼ', label: 'ʼ', semanticLabel: 'modifier apostrophe'),
  ],
  // Nigerian English needs nothing beyond the system keyboard.
  NAtlasLanguage.english: [],
};

/// A row of diacritic keys that sits above the system keyboard.
///
/// Phone keyboards generally cannot produce Yorùbá and Igbo diacritics, so most
/// people type these languages unmarked — but tone is **semantic** in both, and
/// N-ATLaS answers noticeably better on correctly marked input. This bar closes
/// that gap without requiring a custom system keyboard.
///
/// ```dart
/// Column(
///   children: [
///     NAtlasDiacriticBar(
///       controller: _messageController,
///       language: _language,
///     ),
///     TextField(controller: _messageController),
///   ],
/// )
/// ```
///
/// Renders nothing for [NAtlasLanguage.english].
class NAtlasDiacriticBar extends StatelessWidget {
  /// The field this bar types into.
  final TextEditingController controller;

  /// Which key set to show.
  final NAtlasLanguage language;

  /// Called after each insertion, with the field's new text.
  final ValueChanged<String>? onChanged;

  /// Give light haptic feedback on each key. Defaults to true.
  final bool hapticFeedback;

  /// Height of the bar.
  final double height;

  /// Creates a diacritic bar for [language], typing into [controller].
  const NAtlasDiacriticBar({
    super.key,
    required this.controller,
    required this.language,
    this.onChanged,
    this.hapticFeedback = true,
    this.height = 48,
  });

  /// Insert [text] at the cursor, replacing any selection.
  ///
  /// Kept separate from the widget so apps with their own key UI can reuse the
  /// insertion logic.
  static void insertAtCursor(TextEditingController controller, String text) {
    final value = controller.value;
    final selection = value.selection;

    // The field may never have been focused, in which case the selection
    // offset is -1 and replaceRange would throw.
    if (!selection.isValid) {
      final appended = value.text + text;
      controller.value = TextEditingValue(
        text: appended,
        selection: TextSelection.collapsed(offset: appended.length),
      );
      return;
    }

    final newText =
        value.text.replaceRange(selection.start, selection.end, text);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: selection.start + text.length),
      composing: TextRange.empty,
    );
  }

  @override
  Widget build(BuildContext context) {
    final keys = kDiacriticKeys[language] ?? const <DiacriticKey>[];
    if (keys.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: keys.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final key = keys[i];
          return Semantics(
            label: key.semanticLabel,
            button: true,
            child: Material(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  if (hapticFeedback) HapticFeedback.lightImpact();
                  insertAtCursor(controller, key.insert);
                  onChanged?.call(controller.text);
                },
                child: Container(
                  constraints: const BoxConstraints(minWidth: 44),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    key.label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
