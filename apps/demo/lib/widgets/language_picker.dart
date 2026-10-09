import 'package:flutter/material.dart';
import 'package:natlas_flutter/natlas_flutter.dart';

/// App-bar dropdown for switching between the four N-ATLaS languages.
class LanguagePicker extends StatelessWidget {
  final NAtlasLanguage value;
  final ValueChanged<NAtlasLanguage> onChanged;

  const LanguagePicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<NAtlasLanguage>(
      initialValue: value,
      tooltip: 'Language',
      onSelected: onChanged,
      itemBuilder: (context) => NAtlasLanguage.values
          .map(
            (lang) => PopupMenuItem(
              value: lang,
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: lang == value
                        ? const Icon(Icons.check_rounded, size: 18)
                        : null,
                  ),
                  Text(lang.displayName),
                ],
              ),
            ),
          )
          .toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Text(
              value.code.toUpperCase(),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const Icon(Icons.arrow_drop_down_rounded),
          ],
        ),
      ),
    );
  }
}
