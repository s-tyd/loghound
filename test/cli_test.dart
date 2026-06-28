import 'dart:convert';
import 'dart:io';

import 'package:loghound/loghound.dart';
import 'package:loghound/src/cli.dart';
import 'package:test/test.dart';

void main() {
  group('runLogHoundCli', () {
    late Directory directory;
    late File file;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('loghound-cli-');
      file = File('${directory.path}/app.jsonl');
      final store = JsonlLogStore(file);
      await store.append({
        'timestamp': '2026-06-27T10:00:00.000',
        'name': 'HTTP',
        'level': 0,
        'message': 'GET /spots',
      });
      await store.append({
        'timestamp': '2026-06-27T10:01:00.000',
        'name': 'Purchase',
        'level': 900,
        'message': 'purchase natural-wine failed',
        'trace_id': 'trace-1',
        'data': {'request_id': 'request-1'},
      });
      await store.append({
        'timestamp': '2026-06-27T10:02:00.000',
        'name': 'Purchase',
        'level': 1000,
        'message': 'purchase guidebook failed',
        'trace_id': 'trace-2',
      });
    });

    tearDown(() async {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });

    test('query prints matching JSON lines', () async {
      final out = StringBuffer();

      final exitCode = await runLogHoundCli([
        'query',
        '--file',
        file.path,
        '--contains',
        'natural-wine',
      ], out: out);

      expect(exitCode, 0);
      final lines = out.toString().trim().split('\n');
      expect(lines, hasLength(1));
      expect(jsonDecode(lines.single), containsPair('level', 900));
    });

    test('query filters by related identifiers', () async {
      final out = StringBuffer();

      final exitCode = await runLogHoundCli([
        'query',
        '--file',
        file.path,
        '--trace-id',
        'trace-1',
        '--request-id',
        'request-1',
      ], out: out);

      expect(exitCode, 0);
      final lines = out.toString().trim().split('\n');
      expect(lines, hasLength(1));
      expect(
        jsonDecode(lines.single),
        containsPair('message', 'purchase natural-wine failed'),
      );
    });

    test('tail prints the last count records', () async {
      final out = StringBuffer();

      final exitCode = await runLogHoundCli([
        'tail',
        '--file',
        file.path,
        '--count',
        '2',
      ], out: out);

      expect(exitCode, 0);
      final lines = out.toString().trim().split('\n');
      expect(lines, hasLength(2));
      expect(jsonDecode(lines.first), containsPair('level', 900));
      expect(jsonDecode(lines.last), containsPair('level', 1000));
    });

    test(
      'latest-error prints the latest record at warning level or higher',
      () async {
        final out = StringBuffer();

        final exitCode = await runLogHoundCli([
          'latest-error',
          '--file',
          file.path,
        ], out: out);

        expect(exitCode, 0);
        expect(
          jsonDecode(out.toString().trim()),
          containsPair('message', 'purchase guidebook failed'),
        );
      },
    );

    test('context prints markdown around the latest error', () async {
      final store = JsonlLogStore(file);
      await store.append({
        'timestamp': '2026-06-27T10:03:00.000',
        'name': 'HTTP',
        'level': 0,
        'message': 'cleanup after failure',
      });
      final out = StringBuffer();

      final exitCode = await runLogHoundCli([
        'context',
        '--file',
        file.path,
        '--latest-error',
        '--before',
        '1',
        '--after',
        '1',
        '--max-lines',
        '3',
      ], out: out);

      expect(exitCode, 0);
      final text = out.toString();
      expect(text, contains('# loghound context'));
      expect(text, contains('## Latest Error'));
      expect(text, contains('## Related Logs'));
      expect(text, contains('purchase guidebook failed'));
      expect(text, contains('purchase natural-wine failed'));
      expect(text, contains('cleanup after failure'));
      expect(text, isNot(contains('GET /spots')));
    });

    test('context includes logs sharing the latest error trace id', () async {
      final tracedFile = File('${directory.path}/traced.jsonl');
      final store = JsonlLogStore(tracedFile);
      await store.append({
        'timestamp': '2026-06-27T10:00:00.000',
        'level': 0,
        'message': 'request started',
        'trace_id': 'trace-context',
      });
      await store.append({
        'timestamp': '2026-06-27T10:01:00.000',
        'level': 0,
        'message': 'unrelated request',
        'trace_id': 'trace-other',
      });
      await store.append({
        'timestamp': '2026-06-27T10:02:00.000',
        'level': 1000,
        'message': 'request failed',
        'trace_id': 'trace-context',
      });
      final out = StringBuffer();

      final exitCode = await runLogHoundCli([
        'context',
        '--file',
        tracedFile.path,
        '--latest-error',
        '--before',
        '0',
        '--after',
        '0',
      ], out: out);

      expect(exitCode, 0);
      final text = out.toString();
      expect(text, contains('request started'));
      expect(text, contains('request failed'));
      expect(text, isNot(contains('unrelated request')));
    });

    test('context renders an action and HTTP timeline summary', () async {
      final contextFile = File('${directory.path}/timeline.jsonl');
      final store = JsonlLogStore(contextFile);
      await store.append({
        'timestamp': '2026-06-27T10:00:00.000',
        'kind': 'action',
        'name': 'search.submit',
        'screen': 'SpotSearch',
        'data': {'query': 'ramen'},
        'request_id': 'req-1',
      });
      await store.append({
        'timestamp': '2026-06-27T10:00:01.000',
        'kind': 'http',
        'method': 'GET',
        'url': '/spots',
        'status': 200,
        'duration_ms': 120,
        'request_id': 'req-1',
        'response_body_bytes': 1200,
      });
      await store.append({
        'timestamp': '2026-06-27T10:00:02.000',
        'kind': 'error',
        'level': 1000,
        'message': 'empty title rendered',
        'request_id': 'req-1',
      });
      final out = StringBuffer();

      final exitCode = await runLogHoundCli([
        'context',
        '--file',
        contextFile.path,
        '--latest-error',
        '--before',
        '2',
        '--after',
        '0',
      ], out: out);

      expect(exitCode, 0);
      final text = out.toString();
      expect(text, contains('## Timeline Summary'));
      expect(text, contains('Action: search.submit screen=SpotSearch'));
      expect(text, contains('HTTP: GET /spots -> 200 duration=120ms'));
      expect(text, contains('response_body_bytes=1200'));
      expect(text, contains('Error: empty title rendered'));
    });

    test('context respects max chars', () async {
      final out = StringBuffer();

      final exitCode = await runLogHoundCli([
        'context',
        '--file',
        file.path,
        '--latest-error',
        '--max-chars',
        '180',
      ], out: out);

      expect(exitCode, 0);
      expect(out.toString().length, lessThanOrEqualTo(180));
      expect(out.toString(), contains('truncated'));
    });

    test('help lists available commands', () async {
      final out = StringBuffer();

      final exitCode = await runLogHoundCli(['--help'], out: out);

      expect(exitCode, 0);
      expect(out.toString(), contains('serve'));
      expect(out.toString(), contains('stay'));
      expect(out.toString(), contains('apps'));
      expect(out.toString(), contains('sessions'));
      expect(out.toString(), contains('query'));
      expect(out.toString(), contains('tail'));
      expect(out.toString(), contains('latest-error'));
      expect(out.toString(), contains('context'));
      expect(out.toString(), contains('actions'));
      expect(out.toString(), contains('http'));
      expect(out.toString(), contains('body'));
      expect(out.toString(), contains('stats'));
    });

    test('apps and sessions discover legacy routed log files', () async {
      final root = Directory('${directory.path}/routed');
      final routedStore = JsonlLogStore(
        File('${root.path}/guide-app/staging/sessions/session-1.jsonl'),
      );
      await routedStore.append({
        'timestamp': '2026-06-27T10:00:00.000',
        'app_id': 'guide-app',
        'flavor': 'staging',
        'session_id': 'session-1',
        'kind': 'action',
        'name': 'screen.view',
      });

      final appsOut = StringBuffer();
      final appsExit = await runLogHoundCli([
        'apps',
        '--root',
        root.path,
      ], out: appsOut);

      expect(appsExit, 0);
      final app = jsonDecode(appsOut.toString().trim()) as Map<String, Object?>;
      expect(app, containsPair('app_id', 'guide-app'));
      expect(app['flavors'], contains('staging'));

      final sessionsOut = StringBuffer();
      final sessionsExit = await runLogHoundCli([
        'sessions',
        '--root',
        root.path,
        '--app',
        'guide-app',
        '--flavor',
        'staging',
      ], out: sessionsOut);

      expect(sessionsExit, 0);
      final session =
          jsonDecode(sessionsOut.toString().trim()) as Map<String, Object?>;
      expect(session, containsPair('app_id', 'guide-app'));
      expect(session, containsPair('flavor', 'staging'));
      expect(session, containsPair('platform', 'unknown'));
      expect(session, containsPair('session_id', 'session-1'));
    });

    test('routed commands can filter sessions by platform', () async {
      final root = Directory('${directory.path}/platform-routed');
      final routedStore = LogHoundDirectoryStore(root);
      await routedStore.append({
        'timestamp': '2026-06-27T10:00:00.000',
        'app_id': 'guide-app',
        'session_id': 'session-1',
        'platform': 'ios',
        'kind': 'log',
        'message': 'ios log',
      });
      await routedStore.append({
        'timestamp': '2026-06-27T10:00:01.000',
        'app_id': 'guide-app',
        'session_id': 'session-1',
        'platform': 'android',
        'kind': 'log',
        'message': 'android log',
      });

      final sessionsOut = StringBuffer();
      final sessionsExit = await runLogHoundCli([
        'sessions',
        '--root',
        root.path,
        '--app',
        'guide-app',
        '--platform',
        'ios',
      ], out: sessionsOut);

      expect(sessionsExit, 0);
      final session =
          jsonDecode(sessionsOut.toString().trim()) as Map<String, Object?>;
      expect(session, containsPair('platform', 'ios'));
      expect(session['file'], contains('/ios/sessions/session-1.jsonl'));

      final tailOut = StringBuffer();
      final tailExit = await runLogHoundCli([
        'tail',
        '--root',
        root.path,
        '--app',
        'guide-app',
        '--session',
        'session-1',
        '--platform',
        'android',
      ], out: tailOut);

      expect(tailExit, 0);
      expect(tailOut.toString(), contains('android log'));
      expect(tailOut.toString(), isNot(contains('ios log')));
    });

    test(
      'actions, http list, body, and stats inspect a routed session',
      () async {
        final root = Directory('${directory.path}/investigation');
        final routedStore = JsonlLogStore(
          File('${root.path}/staging/ios/sessions/session-1.jsonl'),
        );
        await routedStore.append({
          'timestamp': '2026-06-27T10:00:00.000',
          'app_id': 'guide-app',
          'flavor': 'staging',
          'platform': 'ios',
          'session_id': 'session-1',
          'kind': 'action',
          'name': 'search.submit',
          'screen': 'SpotSearch',
          'data': {
            'query': 'ramen',
            'selectedFilters': ['open_now'],
          },
        });
        await routedStore.append({
          'timestamp': '2026-06-27T10:00:01.000',
          'app_id': 'guide-app',
          'flavor': 'staging',
          'platform': 'ios',
          'session_id': 'session-1',
          'kind': 'http',
          'request_id': 'req-1',
          'method': 'GET',
          'url': '/spots?query=ramen',
          'status': 200,
          'duration_ms': 120,
          'response_body': {
            'items': [
              {'id': 'spot-1', 'title': 'Ramen One'},
              {'id': 'spot-2', 'title': ''},
            ],
          },
        });
        await routedStore.append({
          'timestamp': '2026-06-27T10:00:02.000',
          'app_id': 'guide-app',
          'flavor': 'staging',
          'platform': 'ios',
          'session_id': 'session-1',
          'kind': 'error',
          'level': 1000,
          'request_id': 'req-1',
          'message': 'empty title rendered',
        });

        final actionOut = StringBuffer();
        final actionExit = await runLogHoundCli([
          'actions',
          '--root',
          root.path,
          '--flavor',
          'staging',
          '--platform',
          'ios',
          '--session',
          'session-1',
        ], out: actionOut);

        expect(actionExit, 0);
        expect(
          jsonDecode(actionOut.toString().trim()),
          containsPair('kind', 'action'),
        );

        final httpOut = StringBuffer();
        final httpExit = await runLogHoundCli([
          'http',
          'list',
          '--root',
          root.path,
          '--flavor',
          'staging',
          '--platform',
          'ios',
          '--session',
          'session-1',
        ], out: httpOut);

        expect(httpExit, 0);
        final httpSummary =
            jsonDecode(httpOut.toString().trim()) as Map<String, Object?>;
        expect(httpSummary, containsPair('request_id', 'req-1'));
        expect(httpSummary, containsPair('method', 'GET'));
        expect(httpSummary, containsPair('status', 200));
        expect(httpSummary, isNot(contains('response_body')));

        final bodyOut = StringBuffer();
        final bodyExit = await runLogHoundCli([
          'body',
          '--root',
          root.path,
          '--flavor',
          'staging',
          '--platform',
          'ios',
          '--session',
          'session-1',
          '--request-id',
          'req-1',
          '--response',
          '--json-path',
          r'$.items[1].title',
        ], out: bodyOut);

        expect(bodyExit, 0);
        expect(jsonDecode(bodyOut.toString().trim()), '');

        final statsOut = StringBuffer();
        final statsExit = await runLogHoundCli([
          'stats',
          '--root',
          root.path,
          '--flavor',
          'staging',
          '--platform',
          'ios',
          '--session',
          'session-1',
        ], out: statsOut);

        expect(statsExit, 0);
        final stats =
            jsonDecode(statsOut.toString().trim()) as Map<String, Object?>;
        expect(stats, containsPair('records', 3));
        expect(stats, containsPair('http_records', 1));
        expect(stats, containsPair('action_records', 1));
      },
    );
  });
}
