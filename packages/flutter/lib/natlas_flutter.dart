/// N-ATLaS Flutter SDK
///
/// A Flutter/Dart client for the N-ATLaS multilingual LLM and its ASR models.
/// Supports Hausa, Igbo, Yorùbá, and Nigerian English.
///
/// ```dart
/// final client = NAtlasClient(
///   baseUrl: 'https://your-gateway.modal.run',
///   apiKey: 'your_api_key',
/// );
///
/// // Streaming chat in Hausa
/// await for (final chunk in client.chatStream(
///   messages: [ChatMessage.user('Sannu!')],
///   language: NAtlasLanguage.hausa,
/// )) {
///   print(chunk.delta);
/// }
/// ```
library natlas_flutter;

export 'src/client.dart';
export 'src/language.dart';
export 'src/models/message.dart';
export 'src/models/chat_response.dart';
export 'src/models/transcription.dart';
export 'src/models/natlas_error.dart';
export 'src/widgets/natlas_diacritic_bar.dart';
export 'src/widgets/natlas_mic_button.dart';
export 'src/widgets/natlas_stream_text.dart';
