/// Supported languages in N-ATLaS.
enum NAtlasLanguage {
  hausa('ha'),
  igbo('ig'),
  yoruba('yo'),
  english('en');

  /// The BCP-47 / gateway language code.
  final String code;

  const NAtlasLanguage(this.code);

  /// Human-readable display name.
  String get displayName => switch (this) {
        NAtlasLanguage.hausa => 'Hausa',
        NAtlasLanguage.igbo => 'Igbo',
        NAtlasLanguage.yoruba => 'Yorùbá',
        NAtlasLanguage.english => 'Nigerian English',
      };

  /// Parse from a language code string, e.g. 'ha' → [NAtlasLanguage.hausa].
  static NAtlasLanguage fromCode(String code) {
    return NAtlasLanguage.values.firstWhere(
      (l) => l.code == code,
      orElse: () => throw ArgumentError('Unknown language code: $code'),
    );
  }
}
