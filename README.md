<p align="center">
  <img width="300" alt="loghound" src="assets/loghound-icon-white.png" />
</p>

<p align="center">
  <em>AI-friendly local log investigation harness for Dart and Flutter apps.</em>
</p>

loghound helps an AI agent inspect app behavior without pasting a giant log
file into chat. App code emits structured records through hidden Dart VM
Service events, and the CLI stores those records as local JSON Lines files that
can be queried later.

- **No local server** - use the Dart VM Service in debug/profile sessions.
- **No Flutter log noise** - structured loghound records do not need to appear
  in `flutter logs`.
- **No cloud service** - logs stay in files you choose.
- **Agent-oriented** - query narrow slices, HTTP summaries, bodies, actions,
  and compact context bundles.
- **App-friendly** - development logging is fire-and-forget and never breaks
  the app.

> Security and privacy: loghound can capture real headers, request bodies,
> response bodies, and user-visible text. Redaction is best-effort, not a
> compliance boundary. Treat generated JSONL files as sensitive.

## Install

Use loghound as a dev dependency when you only need the CLI:

```bash
dart pub add dev:loghound
```

Use it as a normal dependency when app code imports the SDK:

```bash
dart pub add loghound
```

For a short global command:

```bash
dart pub global activate loghound
loghound version
loghound update
```

## Quick Start

Run your Flutter app through loghound:

```bash
loghound run
```

`loghound run` uses `.fvm/flutter_sdk/bin/flutter` automatically when the
project uses FVM. It starts `flutter run`, captures hidden VM Service extension
events, and writes JSONL records under `.loghound/`.

Common Flutter launch arguments can be passed directly:

```bash
loghound run --flavor dev --dart-define-from-file=.env
```

Device selection is optional. When needed, use the same device id or name you
would pass to `flutter run`.

If you want the collector and Flutter process split across terminals, start the
collector first:

```bash
loghound stay
flutter run
```

`LogHound.run` stamps `app_id`, `flavor`, `platform`, and `session_id` for
events it emits. The CLI routes captured records under:

```text
.loghound/<flavor>/<platform>/sessions/<session_id>.jsonl
.loghound/<flavor>/<platform>/latest.jsonl
.loghound/catalog.jsonl
```

Then inspect only the slice you need:

```bash
loghound apps
loghound sessions --flavor staging
loghound doctor --flavor staging --platform ios --session session-1
loghound actions --flavor staging --platform ios --session session-1
loghound http list --flavor staging --platform ios --session session-1
loghound body --flavor staging --platform ios --session session-1 --request-id req-1 --response --json-path '$.items[0]'
loghound context --flavor staging --platform ios --session session-1 --latest-error
```

## Flutter Bootstrap

Wrap debug startup once:

```dart
import 'package:loghound/loghound.dart';

void main() {
  LogHound.run(
    appId: 'guide-app',
    flavor: appFlavor,
    app: () => runApp(const App()),
  );
}
```

This emits a `session.start` record, captures `print`, captures uncaught zone
errors, and stamps later `LogHound.action`, `LogHound.screen`,
`LogHound.error`, and `LogHound.http` calls. It is debug-only by default.

## Dart Client

Use `LogHoundClient` directly from debug/profile app code or custom logging
code that is observed through the VM Service:

```dart
import 'package:loghound/loghound.dart';

final logs = LogHoundClient();

logs.send({
  'timestamp': DateTime.now().toIso8601String(),
  'app_id': 'guide-app',
  'flavor': 'staging',
  'platform': 'ios',
  'session_id': 'session-1',
  'kind': 'action',
  'name': 'purchase.failed',
  'data': {'productId': 'guidebook.natural_wine'},
});
```

## CLI

```bash
loghound version                            # installed CLI version
loghound update                             # update global activation
loghound run                                # flutter run + hidden collector
loghound stay                                # hidden collector only
loghound apps
loghound sessions --flavor staging
loghound doctor --flavor staging --platform ios
loghound query --contains purchase
loghound tail --flavor staging --platform ios
loghound http list --flavor staging --platform ios --session session-1 --path /api/pages/me/messages --limit 20
loghound http summary --flavor staging --platform ios --session session-1
loghound latest-error --flavor staging
loghound context --flavor staging --latest-error
loghound context --flavor staging --platform ios --session session-1 --around-http /api/pages/me/messages
```

`doctor` reports whether routed logs are ready for AI investigation: sessions,
records, screen/action/http/error counts, HTTP body capture, stale records when
`--max-age-minutes` is passed, and actionable warnings. When HTTP records exist
but bodies are missing, `doctor` reports the body-capture settings and Flutter
launch flags to check. `query`, `latest-error`, and `context` understand common
OpenTelemetry fields such as `severity_number`, `severity_text`, `body`,
`attributes`, `trace_id`, and `span_id`.

HTTP investigation commands can stay narrow without shell `rg`:

```bash
loghound http list --session session-1 --path /api/pages/me/messages --method GET --status 200 --limit 20
loghound http list --session session-1 --contains official_information --since 2026-07-09T02:00:00
loghound http summary --session session-1
loghound context --session session-1 --around-http /api/pages/me/messages --before 20 --after 10
```

`http list` summaries include `request_body_captured` and
`response_body_captured`, so `response_body_bytes:0` is not confused with a
captured empty response.

## HTTP And Action Capture

Add semantic operation logs where AI should understand user intent:

```dart
LogHound.action('search.submit', data: {
  'query': query,
  'selectedFilters': selectedFilters,
});

LogHound.screen('SpotSearch', route: '/spots/search');
```

Manual HTTP events can be emitted today:

```dart
LogHound.http(
  method: 'GET',
  url: '/spots',
  requestId: 'req-1',
  status: 200,
  responseBody: {'items': items},
);
```

Dio apps can install the built-in interceptor:

```dart
import 'package:loghound/loghound_dio.dart';

dio.interceptors.add(LogHoundDioInterceptor());
```

`LogHoundDioInterceptor` captures method, URL, path, status, duration, headers,
and optional request/response bodies. Body capture is opt-in because bodies can
be large and sensitive.

Enable body capture through app launch settings:

```text
LOGHOUND_CAPTURE_HTTP_REQUEST_BODY=false
LOGHOUND_CAPTURE_HTTP_RESPONSE_BODY=true
```

Then pass the settings into Flutter, for example:

```bash
loghound run --flavor dev --dart-define-from-file=.env
flutter run --dart-define=LOGHOUND_CAPTURE_HTTP_RESPONSE_BODY=true
```

The same policy is visible in `loghound setting` as
`capture_http_request_body` and `capture_http_response_body`, so an AI agent can
notice when HTTP bodies are expected but missing from the logs.

If `loghound doctor` reports `no_http_bodies`, enable the expected policy and
launch the app with matching Dart defines:

```bash
loghound setting capture_http_response_body true
loghound setting capture_http_request_body true
loghound run --flavor dev --dart-define-from-file=.env
flutter run --dart-define=LOGHOUND_CAPTURE_HTTP_RESPONSE_BODY=true
flutter run --dart-define=LOGHOUND_CAPTURE_HTTP_REQUEST_BODY=true
```

HTTP helper bodies are redacted before printing and are capped by default:
request bodies at 64 KB and response bodies at 256 KB. Truncated records keep
`request_body_bytes`, `response_body_bytes`, and `*_body_truncated` metadata.

## Redaction

The default redactor masks common secret keys such as `authorization`,
`cookie`, `password`, `secret`, `token`, `x-api-key`, and `x-staging-auth`. It
also masks common secret-looking values such as bearer tokens, JWTs, GitHub
tokens, AWS access keys, secret URL query values, and email addresses.

```dart
final redactor = LogHoundRedactor(sensitiveKeys: {'api_key'});
```

Redaction is best-effort. Do not treat it as a compliance boundary.

## AI Agent Workflow

loghound is intended to be operated by AI agents. The developer can use
`loghound run` for app startup, or keep `loghound stay` running as a hidden
collector. The agent discovers apps and sessions, reads semantic action
timelines, inspects HTTP calls by request ID, and drills into request or
response bodies only when needed.

The raw local store can stay rich while the AI sees focused command output.

## Roadmap

loghound is pre-1.0; public APIs can still change. Near-term work includes
automatic Dio/`http` body capture, Flutter widget helpers for semantic actions,
stronger redaction policy, and retention/cleanup commands.
