import 'package:flutter/material.dart';
import 'package:natlas_flutter/natlas_flutter.dart';

import '../services/settings_store.dart';
import 'chat_screen.dart';

/// Gateway URL, API key, and language. Shown on first run, reachable later
/// from the app bar.
class SettingsScreen extends StatefulWidget {
  final SettingsStore settings;
  final bool isFirstRun;

  const SettingsScreen({
    super.key,
    required this.settings,
    this.isFirstRun = false,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  late NAtlasLanguage _language;

  final _formKey = GlobalKey<FormState>();
  bool _testing = false;
  String? _testResult;
  bool _testPassed = false;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _baseUrl = TextEditingController(text: widget.settings.baseUrl);
    _apiKey = TextEditingController(text: widget.settings.apiKey);
    _language = widget.settings.language;
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  // ── Connection test ───────────────────────────────────────────────────────

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _testing = true;
      _testResult = null;
      _testPassed = false;
    });

    final client = NAtlasClient(
      baseUrl: _baseUrl.text.trim(),
      apiKey: _apiKey.text.trim(),
      timeout: const Duration(seconds: 30),
    );

    try {
      final health = await client.health();
      final asr = (health['models'] as Map?)?['asr'] as List?;
      if (!mounted) return;
      setState(() {
        _testPassed = health['status'] == 'ok';
        _testResult = _testPassed
            ? 'Connected · ${asr?.length ?? 0} ASR models loaded'
            : 'Gateway responded but status is "${health['status']}"';
      });
    } on NAtlasException catch (e) {
      if (!mounted) return;
      setState(() => _testResult = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _testResult = 'Could not reach the gateway: $e');
    } finally {
      client.dispose();
      if (mounted) setState(() => _testing = false);
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    widget.settings
      ..baseUrl = _baseUrl.text.trim()
      ..apiKey = _apiKey.text.trim()
      ..language = _language;
    await widget.settings.save();

    if (!mounted) return;

    if (widget.isFirstRun) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ChatScreen(settings: widget.settings),
      ));
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isFirstRun ? 'Connect your gateway' : 'Settings'),
        automaticallyImplyLeading: !widget.isFirstRun,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (widget.isFirstRun) ...[
              Text(
                'This demo talks to a self-hosted N-ATLaS gateway. Deploy one '
                'with `modal deploy serve/modal_app.py`, then paste its URL and '
                'API key below.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
            ],
            TextFormField(
              controller: _baseUrl,
              decoration: const InputDecoration(
                labelText: 'Gateway URL',
                hintText: 'https://your-app.modal.run',
                prefixIcon: Icon(Icons.cloud_outlined),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return 'Required';
                final uri = Uri.tryParse(text);
                if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
                  return 'Enter a full URL, including https://';
                }
                if (uri.scheme != 'https' && uri.host != 'localhost') {
                  return 'Use https (or localhost for local testing)';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _apiKey,
              obscureText: _obscureKey,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'API key',
                prefixIcon: const Icon(Icons.key_outlined),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscureKey
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                ),
              ),
              validator: (value) =>
                  (value?.trim().isEmpty ?? true) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<NAtlasLanguage>(
              initialValue: _language,
              decoration: const InputDecoration(
                labelText: 'Language',
                prefixIcon: Icon(Icons.translate_rounded),
                border: OutlineInputBorder(),
              ),
              items: NAtlasLanguage.values
                  .map((lang) => DropdownMenuItem(
                        value: lang,
                        child: Text('${lang.displayName} (${lang.code})'),
                      ))
                  .toList(),
              onChanged: (lang) {
                if (lang != null) setState(() => _language = lang);
              },
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _testing ? null : _testConnection,
              icon: _testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.network_check_rounded),
              label: Text(_testing ? 'Testing…' : 'Test connection'),
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _testPassed
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _testPassed
                          ? Icons.check_circle_outline_rounded
                          : Icons.error_outline_rounded,
                      size: 20,
                      color: _testPassed
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _testResult!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _testPassed
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _save,
              child: Text(widget.isFirstRun ? 'Start chatting' : 'Save'),
            ),
            const SizedBox(height: 32),
            Text(
              'N-ATLaS is an initiative of the Federal Ministry of '
              'Communications, Innovation and Digital Economy, and powered by '
              'Awarri Technologies.',
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
