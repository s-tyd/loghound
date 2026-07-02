import 'package:loghound/loghound.dart';

Future<void> main() async {
  final client = LogHoundClient();

  try {
    client.send({
      'timestamp': DateTime.now().toIso8601String(),
      'name': 'HTTP',
      'level': 800,
      'message': 'GET /api/spots completed',
      'data': {'statusCode': 200, 'durationMs': 42},
    });

    await client.flush();
  } finally {
    client.close();
  }
}
