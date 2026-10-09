import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'language.dart';
import 'models/chat_response.dart';
import 'models/message.dart';
import 'models/natlas_error.dart';
import 'models/transcription.dart';

/// Client for the N-ATLaS gateway.
///
/// ```dart
/// final client = NAtlasClient(
///   baseUrl: 'https://your-gateway.modal.run',
///   apiKey: 'your_api_key',
/// );
/// ```
class NAtlasClient {
  final String baseUrl;
  final String apiKey;
  final http.Client _http;
  final Duration timeout;

  NAtlasClient({
    required this.baseUrl,
    required this.apiKey,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 60),
  }) : _http = httpClient ?? http.Client();

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  Uri _uri(String path) => Uri.parse('${baseUrl.trimRight()}$path');

  // ── Chat (non-streaming) ─────────────────────────────────────────────────

  /// Send messages and receive the full reply at once.
  Future<ChatResponse> chat({
    required List<ChatMessage> messages,
    NAtlasLanguage language = NAtlasLanguage.english,
    double temperature = 0.7,
    int maxTokens = 512,
  }) async {
    final body = jsonEncode({
      'messages': messages.map((m) => m.toJson()).toList(),
      'language': language.code,
      'temperature': temperature,
      'max_tokens': maxTokens,
      'stream': false,
    });

    final response = await _http
        .post(_uri('/v1/chat/completions'), headers: _headers, body: body)
        .timeout(timeout);

    _checkStatus(response);
    return ChatResponse.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  // ── Chat (streaming) ─────────────────────────────────────────────────────

  /// Stream the reply as it is generated, yielding [ChatStreamChunk]s.
  Stream<ChatStreamChunk> chatStream({
    required List<ChatMessage> messages,
    NAtlasLanguage language = NAtlasLanguage.english,
    double temperature = 0.7,
    int maxTokens = 512,
  }) async* {
    final body = jsonEncode({
      'messages': messages.map((m) => m.toJson()).toList(),
      'language': language.code,
      'temperature': temperature,
      'max_tokens': maxTokens,
      'stream': true,
    });

    final request = http.Request('POST', _uri('/v1/chat/completions'));
    request.headers.addAll({
      ..._headers,
      'Accept': 'text/event-stream',
    });
    request.body = body;

    final streamedResponse =
        await _http.send(request).timeout(timeout);

    if (streamedResponse.statusCode != 200) {
      final errorBody = await streamedResponse.stream.bytesToString();
      throw NAtlasException.fromStatus(streamedResponse.statusCode, errorBody);
    }

    // utf8.decoder then LineSplitter buffers across TCP chunk boundaries, so a
    // `data:` line split mid-flight is reassembled before we parse it.
    final lines = streamedResponse.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
      if (!line.startsWith('data: ')) continue;
      final data = line.substring(6).trim();
      if (data == '[DONE]') break;
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final chunk = ChatStreamChunk.fromJson(json);
        if (chunk.delta.isNotEmpty) yield chunk;
      } catch (_) {
        // Malformed SSE line — skip
      }
    }
  }

  // ── Transcription ────────────────────────────────────────────────────────

  /// Transcribe audio bytes to text.
  ///
  /// [audio] can be ogg/opus, mp3, m4a, wav, or any format ffmpeg supports.
  /// The gateway handles conversion to 16 kHz mono WAV internally.
  Future<TranscriptionResult> transcribe({
    required Uint8List audio,
    required NAtlasLanguage language,
    String filename = 'audio.ogg',
  }) async {
    final ext = filename.split('.').last;
    final mimeType = _mimeForExt(ext);

    final request =
        http.MultipartRequest('POST', _uri('/v1/audio/transcriptions'));
    request.headers['Authorization'] = 'Bearer $apiKey';
    request.fields['language'] = language.code;
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      audio,
      filename: filename,
      contentType: MediaType.parse(mimeType),
    ));

    final streamedResponse = await _http.send(request).timeout(timeout);
    final responseBody = await streamedResponse.stream.bytesToString();

    if (streamedResponse.statusCode != 200) {
      throw NAtlasException.fromStatus(streamedResponse.statusCode, responseBody);
    }

    return TranscriptionResult.fromJson(
        jsonDecode(responseBody) as Map<String, dynamic>);
  }

  // ── Voice chat ───────────────────────────────────────────────────────────

  /// Transcribe audio then send the transcript to N-ATLaS and return both.
  Future<VoiceChatResult> voiceChat({
    required Uint8List audio,
    required NAtlasLanguage language,
    String filename = 'audio.ogg',
    List<ChatMessage> history = const [],
    double temperature = 0.7,
    int maxTokens = 512,
  }) async {
    final transcription = await transcribe(
      audio: audio,
      language: language,
      filename: filename,
    );

    final messages = [
      ...history,
      ChatMessage.user(transcription.text),
    ];

    final response = await chat(
      messages: messages,
      language: language,
      temperature: temperature,
      maxTokens: maxTokens,
    );

    return VoiceChatResult(
      transcript: transcription,
      reply: response.content,
    );
  }

  // ── Health ───────────────────────────────────────────────────────────────

  /// Check that the gateway is alive and models are loaded.
  Future<Map<String, dynamic>> health() async {
    final response =
        await _http.get(_uri('/health'), headers: {'Accept': 'application/json'}).timeout(timeout);
    _checkStatus(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // ── Internals ────────────────────────────────────────────────────────────

  void _checkStatus(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NAtlasException.fromStatus(response.statusCode, response.body);
    }
  }

  static String _mimeForExt(String ext) => switch (ext.toLowerCase()) {
        'ogg' => 'audio/ogg',
        'mp3' => 'audio/mpeg',
        'm4a' => 'audio/m4a',
        'wav' => 'audio/wav',
        'webm' => 'audio/webm',
        _ => 'application/octet-stream',
      };

  /// Release the underlying HTTP client. Call when the client is no longer needed.
  void dispose() => _http.close();
}
