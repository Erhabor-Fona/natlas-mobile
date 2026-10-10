import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:natlas_flutter/natlas_flutter.dart';

import 'fixtures.dart';

void main() {
  group('NAtlasLanguage', () {
    test('codes map to the gateway contract', () {
      expect(NAtlasLanguage.hausa.code, 'ha');
      expect(NAtlasLanguage.igbo.code, 'ig');
      expect(NAtlasLanguage.yoruba.code, 'yo');
      expect(NAtlasLanguage.english.code, 'en');
    });

    test('fromCode round-trips', () {
      for (final lang in NAtlasLanguage.values) {
        expect(NAtlasLanguage.fromCode(lang.code), lang);
      }
    });

    test('fromCode rejects unknown codes', () {
      expect(() => NAtlasLanguage.fromCode('fr'), throwsArgumentError);
    });

    test('display names are correct', () {
      expect(NAtlasLanguage.yoruba.displayName, 'Yorùbá');
      expect(NAtlasLanguage.english.displayName, 'Nigerian English');
    });
  });

  group('ChatMessage', () {
    test('factories set the right role', () {
      expect(ChatMessage.user('hi').role, 'user');
      expect(ChatMessage.assistant('hi').role, 'assistant');
      expect(ChatMessage.system('hi').role, 'system');
    });

    test('serialises to the wire format', () {
      expect(
        ChatMessage.user('Sannu!').toJson(),
        {'role': 'user', 'content': 'Sannu!'},
      );
    });
  });

  group('ChatResponse.fromJson', () {
    test('parses the shared fixture', () {
      final json =
          jsonDecode(loadFixture('chat_response.json')) as Map<String, dynamic>;
      final response = ChatResponse.fromJson(json);

      expect(response.id, 'chatcmpl-8f2a1c4e9b7d4e0a');
      expect(response.content, contains('Sannu da zuwa'));
      expect(response.promptTokens, 42);
      expect(response.completionTokens, 18);
      expect(response.totalTokens, 60);
    });

    test('tolerates a missing usage block', () {
      final response = ChatResponse.fromJson({
        'id': 'x',
        'choices': [
          {
            'index': 0,
            'message': {'role': 'assistant', 'content': 'hi'}
          }
        ],
      });
      expect(response.promptTokens, 0);
      expect(response.completionTokens, 0);
    });
  });

  group('TranscriptionResult.fromJson', () {
    test('parses the shared fixture', () {
      final json = jsonDecode(loadFixture('transcription_response.json'))
          as Map<String, dynamic>;
      final result = TranscriptionResult.fromJson(json);

      expect(result.text, 'Ina son sanin yadda ake noma masara a Kano.');
      expect(result.language, NAtlasLanguage.hausa);
      expect(result.durationSeconds, closeTo(4.82, 0.001));
    });
  });

  group('NAtlasClient.chat', () {
    test('sends the documented request body', () async {
      Map<String, dynamic>? sentBody;

      final client = NAtlasClient(
        baseUrl: 'https://gateway.test',
        apiKey: 'test_key',
        httpClient: MockClient((request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          expect(request.url.path, '/v1/chat/completions');
          expect(request.headers['Authorization'], 'Bearer test_key');
          return http.Response(
            loadFixture('chat_response.json'),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final response = await client.chat(
        messages: [ChatMessage.user('Sannu! Yaya aiki?')],
        language: NAtlasLanguage.hausa,
      );

      expect(sentBody!['language'], 'ha');
      expect(sentBody!['stream'], false);
      expect(sentBody!['temperature'], 0.7);
      expect(sentBody!['max_tokens'], 512);
      expect(sentBody!['messages'], [
        {'role': 'user', 'content': 'Sannu! Yaya aiki?'}
      ]);
      expect(response.content, contains('Sannu da zuwa'));
    });

    test('throws NAtlasException on 401', () async {
      final client = NAtlasClient(
        baseUrl: 'https://gateway.test',
        apiKey: 'wrong',
        httpClient: MockClient(
            (_) async => http.Response(loadFixture('error_401.json'), 401)),
      );

      expect(
        () => client.chat(
          messages: [ChatMessage.user('hi')],
          language: NAtlasLanguage.english,
        ),
        throwsA(isA<NAtlasException>().having(
          (e) => e.statusCode,
          'statusCode',
          401,
        )),
      );
    });
  });

  group('NAtlasClient.chatStream', () {
    test('yields deltas and stops at [DONE]', () async {
      final client = NAtlasClient(
        baseUrl: 'https://gateway.test',
        apiKey: 'test_key',
        httpClient: MockClient.streaming((request, bodyStream) async {
          return http.StreamedResponse(
            Stream.value(utf8.encode(loadFixture('chat_stream.txt'))),
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }),
      );

      final deltas = <String>[];
      await for (final chunk in client.chatStream(
        messages: [ChatMessage.user('Sannu!')],
        language: NAtlasLanguage.hausa,
      )) {
        deltas.add(chunk.delta);
      }

      expect(deltas, ['Sannu', ' da', ' zuwa', '!']);
      expect(deltas.join(), 'Sannu da zuwa!');
    });
  });

  group('NAtlasClient.transcribe', () {
    test('posts multipart with the language field', () async {
      final client = NAtlasClient(
        baseUrl: 'https://gateway.test',
        apiKey: 'test_key',
        httpClient: MockClient.streaming((request, bodyStream) async {
          expect(request.url.path, '/v1/audio/transcriptions');
          expect(
            request.headers['content-type'],
            contains('multipart/form-data'),
          );
          final body = await bodyStream.bytesToString();
          expect(body, contains('name="language"'));
          expect(body, contains('ha'));
          expect(body, contains('filename="recording.m4a"'));
          return http.StreamedResponse(
            Stream.value(
                utf8.encode(loadFixture('transcription_response.json'))),
            200,
          );
        }),
      );

      final result = await client.transcribe(
        audio: Uint8List.fromList([0, 1, 2, 3]),
        language: NAtlasLanguage.hausa,
        filename: 'recording.m4a',
      );

      expect(result.text, contains('noma masara'));
      expect(result.language, NAtlasLanguage.hausa);
    });
  });

  group('NAtlasClient.health', () {
    test('parses the shared fixture', () async {
      final client = NAtlasClient(
        baseUrl: 'https://gateway.test',
        apiKey: 'test_key',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/health');
          return http.Response(loadFixture('health_response.json'), 200);
        }),
      );

      final health = await client.health();
      expect(health['status'], 'ok');
      expect((health['models'] as Map)['llm'], 'NCAIR1/N-ATLaS');
      expect((health['models'] as Map)['asr'], hasLength(4));
    });
  });
}
