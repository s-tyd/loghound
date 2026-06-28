import 'package:loghound/loghound.dart';

Future<void> main() async {
  final client = LogHoundClient(Uri.parse('http://127.0.0.1:8765/logs'));

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
