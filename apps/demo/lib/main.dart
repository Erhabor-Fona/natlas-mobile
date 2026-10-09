import 'package:flutter/material.dart';

import 'screens/chat_screen.dart';
import 'screens/settings_screen.dart';
import 'services/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await SettingsStore.load();
  runApp(NAtlasDemoApp(settings: settings));
}

class NAtlasDemoApp extends StatelessWidget {
  final SettingsStore settings;

  const NAtlasDemoApp({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'N-ATLaS Demo',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: settings.isConfigured
          ? ChatScreen(settings: settings)
          : SettingsScreen(settings: settings, isFirstRun: true),
    );
  }

  ThemeData _theme(Brightness brightness) {
    // Nigerian green as the seed colour.
    const seed = Color(0xFF008751);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: brightness,
      ),
      appBarTheme: const AppBarTheme(centerTitle: false),
    );
  }
}
