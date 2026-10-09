import 'package:natlas_flutter/natlas_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the gateway URL, API key, and chosen language between launches.
///
/// The API key is stored in SharedPreferences, which is adequate for a demo
/// but not for production — use flutter_secure_storage or the platform
/// keychain in a shipped app.
class SettingsStore {
  static const _keyBaseUrl = 'natlas_base_url';
  static const _keyApiKey = 'natlas_api_key';
  static const _keyLanguage = 'natlas_language';

  String baseUrl;
  String apiKey;
  NAtlasLanguage language;

  SettingsStore({
    required this.baseUrl,
    required this.apiKey,
    required this.language,
  });

  /// True when both the gateway URL and the API key are present.
  bool get isConfigured => baseUrl.isNotEmpty && apiKey.isNotEmpty;

  static Future<SettingsStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_keyLanguage) ?? 'ha';

    return SettingsStore(
      baseUrl: prefs.getString(_keyBaseUrl) ?? '',
      apiKey: prefs.getString(_keyApiKey) ?? '',
      language: _parseLanguage(code),
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBaseUrl, baseUrl.trim());
    await prefs.setString(_keyApiKey, apiKey.trim());
    await prefs.setString(_keyLanguage, language.code);
  }

  /// Build a client from the stored settings.
  NAtlasClient buildClient() => NAtlasClient(
        baseUrl: baseUrl.trim(),
        apiKey: apiKey.trim(),
        timeout: const Duration(minutes: 3),
      );

  static NAtlasLanguage _parseLanguage(String code) {
    try {
      return NAtlasLanguage.fromCode(code);
    } on ArgumentError {
      return NAtlasLanguage.hausa;
    }
  }
}
