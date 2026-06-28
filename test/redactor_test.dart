import 'package:loghound/loghound.dart';
import 'package:test/test.dart';

void main() {
  group('LogHoundRedactor', () {
    test('masks sensitive map keys recursively', () {
      final redactor = LogHoundRedactor();

      final result = redactor.redact({
        'authorization': 'Bearer token-123',
        'headers': {
          'Cookie': 'session=abc',
          'x-staging-auth': 'staging-secret',
        },
        'message': 'ok',
      });

      expect(result, {
        'authorization': '***',
        'headers': {'Cookie': '***', 'x-staging-auth': '***'},
        'message': 'ok',
      });
    });

    test('masks inline header-like values in strings', () {
      final redactor = LogHoundRedactor();

      final result = redactor.redact(
        'Headers: {Authorization: Bearer abc, X-Staging-Auth: secret}',
      );

      expect(result, 'Headers: {Authorization: ***, X-Staging-Auth: ***}');
    });

    test('supports custom sensitive keys', () {
      final redactor = LogHoundRedactor(sensitiveKeys: {'api_key'});

      final result = redactor.redact({'api_key': 'secret', 'name': 'HTTP'});

      expect(result, {'api_key': '***', 'name': 'HTTP'});
    });

    test('masks common secret value patterns in strings', () {
      final redactor = LogHoundRedactor();
      const awsKey =
          'AKIA'
          '1234567890ABCDEF';

      final result =
          redactor.redact(
                'Bearer abc.def.ghi '
                'token=ghp_abcdefghijklmnopqrstuvwxyz123456 '
                'aws=$awsKey '
                'url=https://example.test/callback?access_token=secret123 '
                'email=dev@example.test',
              )
              as String;

      expect(result, isNot(contains('abc.def.ghi')));
      expect(result, isNot(contains('ghp_abcdefghijklmnopqrstuvwxyz123456')));
      expect(result, isNot(contains(awsKey)));
      expect(result, isNot(contains('access_token=secret123')));
      expect(result, isNot(contains('dev@example.test')));
      expect(result, contains('Bearer ***'));
    });

    test('masks JWT-like values', () {
      final redactor = LogHoundRedactor();
      const jwt =
          'eyJhbGciOiJIUzI1NiJ9'
          '.eyJzdWIiOiIxMjM0In0'
          '.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c';

      expect(redactor.redact(jwt), '***');
    });

    test('keeps ordinary dotted identifiers', () {
      final redactor = LogHoundRedactor();

      final result = redactor.redact({
        'name': 'Checkout',
        'message': 'purchase.guidebook.failed',
        'event': 'auth.login.success',
        'package': 'com.example.app',
      });

      expect(result, {
        'name': 'Checkout',
        'message': 'purchase.guidebook.failed',
        'event': 'auth.login.success',
        'package': 'com.example.app',
      });
    });
  });
}
