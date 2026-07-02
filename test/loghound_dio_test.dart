import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:loghound/loghound.dart';
import 'package:loghound/loghound_dio.dart';
import 'package:test/test.dart';

void main() {
  group('LogHoundDioInterceptor', () {
    late List<Map<String, Object?>> sent;

    setUp(() {
      sent = [];
      LogHound.configure(
        LogHoundSession(
          config: const LogHoundSessionConfig(
            appId: 'guide-app',
            flavor: 'staging',
            sessionId: 'session-1',
          ),
          sendRecord: sent.add,
        ),
      );
    });

    tearDown(LogHound.dispose);

    test('exposes dart-define keys for body capture settings', () {
      final interceptor = LogHoundDioInterceptor();

      expect(
        LogHoundDioInterceptor.captureRequestBodyEnvironmentKey,
        'LOGHOUND_CAPTURE_HTTP_REQUEST_BODY',
      );
      expect(
        LogHoundDioInterceptor.captureResponseBodyEnvironmentKey,
        'LOGHOUND_CAPTURE_HTTP_RESPONSE_BODY',
      );
      expect(interceptor.captureRequestBody, isFalse);
      expect(interceptor.captureResponseBody, isFalse);
    });

    test(
      'captures successful Dio responses as structured HTTP records',
      () async {
        final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'));
        dio.httpClientAdapter = _FakeAdapter(
          ResponseBody.fromString(
            '{"items":[{"title":"Guide"}]}',
            200,
            headers: {
              'content-type': ['application/json'],
              'x-request-id': ['server-req-1'],
            },
          ),
        );
        dio.interceptors.add(
          LogHoundDioInterceptor(
            captureRequestBody: true,
            captureResponseBody: true,
          ),
        );

        await dio.post<dynamic>(
          '/search',
          data: {'query': 'ramen', 'password': 'secret'},
          options: Options(headers: {'Authorization': 'Bearer abc'}),
        );
        await LogHound.flush();

        expect(sent, hasLength(1));
        final record = sent.single;
        expect(record, containsPair('kind', 'http'));
        expect(record, containsPair('name', 'HTTP'));
        expect(record, containsPair('method', 'POST'));
        expect(record, containsPair('url', 'https://api.example.test/search'));
        expect(record, containsPair('path', '/search'));
        expect(record, containsPair('status', 200));
        expect(record['request_id'], isA<String>());
        expect(record['duration_ms'], isA<int>());
        expect(record['request_headers'], containsPair('Authorization', '***'));
        expect(
          record['response_headers'],
          containsPair('x-request-id', ['server-req-1']),
        );
        expect(record['request_body'], {'query': 'ramen', 'password': '***'});
        expect(record['response_body'], {
          'items': [
            {'title': 'Guide'},
          ],
        });
        expect(record['response_body_bytes'], greaterThan(0));
      },
    );

    test('captures Dio errors as warning HTTP records', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'));
      dio.httpClientAdapter = _FakeAdapter(
        ResponseBody.fromString(
          '{"message":"down"}',
          503,
          headers: {
            'content-type': ['application/json'],
          },
        ),
      );
      dio.interceptors.add(LogHoundDioInterceptor(captureResponseBody: true));

      await expectLater(
        dio.get<dynamic>('/status'),
        throwsA(isA<DioException>()),
      );
      await LogHound.flush();

      expect(sent, hasLength(1));
      final record = sent.single;
      expect(record, containsPair('kind', 'http'));
      expect(record, containsPair('level', 900));
      expect(record, containsPair('method', 'GET'));
      expect(record, containsPair('url', 'https://api.example.test/status'));
      expect(record, containsPair('path', '/status'));
      expect(record, containsPair('status', 503));
      expect(record, containsPair('error_type', 'badResponse'));
      expect(record['error_message'], isA<String>());
      expect(record['response_body'], {'message': 'down'});
    });
  });
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.responseBody);

  final ResponseBody responseBody;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return responseBody;
  }
}
