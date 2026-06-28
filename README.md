<p align="center">
  <img width="300" alt="loghound" src="assets/loghound-icon-white.png" />
</p>

<p align="center">
  <em>AI-friendly local log investigation harness for Dart and Flutter apps.</em>
</p>

<p align="center">
  <a href="https://pub.dev/packages/loghound"><img src="https://img.shields.io/pub/v/loghound.svg" alt="pub package"></a>
  <a href="https://github.com/s-tyd/loghound/actions/workflows/dart.yml"><img src="https://github.com/s-tyd/loghound/actions/workflows/dart.yml/badge.svg" alt="CI"></a>
  <a href="https://pub.dev/packages/loghound/score"><img src="https://img.shields.io/pub/points/loghound" alt="pub points"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
</p>

loghound is a small Dart package and CLI for collecting development logs on
your own machine so an AI agent can inspect them without asking you to paste a
large file into chat. It receives JSON logs over local HTTP, stores them as
JSON Lines (JSONL), and exposes focused commands for querying only the slice
needed to debug a problem.

- **Local-first** — run the receiver on your workstation or LAN.
- **No cloud service** — logs are written to a file you choose, with no account.
- **Agent-oriented** — tail, filter, inspect, and build compact context bundles
  through commands an AI assistant can run.
- **App-friendly** — use the fire-and-forget Dart client without breaking app
  flows.

> **⚠️ Security & privacy:** loghound captures real HTTP bodies, headers, and
> user-visible text on your machine. Built-in redaction is **best-effort, not a
> compliance boundary**, and the receiver accepts **unauthenticated** `POST`
> requests (bound to `127.0.0.1` by default). Run it only on trusted development
> machines, never expose the port to the internet, and treat the log directory as
> sensitive. Details: [Redaction](#redaction), [Privacy model](#privacy-model),
> and [SECURITY.md](SECURITY.md).

## Contents

- [Why loghound?](#why-loghound)
- [Platform support](#platform-support)
- [Install](#install)
- [Quick start](#quick-start)
- [CLI](#cli)
- [Dart client](#dart-client)
- [Flutter bootstrap](#flutter-bootstrap)
- [HTTP and action capture](#http-and-action-capture)
- [Redaction](#redaction)
- [JSON Lines and OpenTelemetry](#json-lines-and-opentelemetry)
- [AI agent workflow](#ai-agent-workflow)
- [Privacy model](#privacy-model)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
- [License](#license)

## Why loghound?

Debugging a Flutter or Dart app with an AI assistant usually means pasting a
giant log file into chat. That floods the context window, leaks secrets, and
buries the few lines that actually matter.

loghound takes a different approach: **keep a thick local store, expose thin
views.**

- The raw local store keeps rich data — HTTP bodies, redacted headers, screen
  transitions, user actions, and errors.
- The CLI exposes focused commands — lists, filtered slices, JSON-path reads,
  and compact context bundles.

The command surface is designed for an AI agent to ask loghound one precise
question at a time instead of dumping everything:

```bash
loghound apps                                   # where to look
loghound sessions --flavor staging
loghound http list --flavor staging --platform ios --session session-1
loghound http show --flavor staging --platform ios --session session-1 --request-id req_abc
loghound body --flavor staging --platform ios --session session-1 --request-id req_abc --response --json-path '$.items[1]'
loghound context --flavor staging --platform ios --session session-1 --latest-error
```

Humans can run the same commands, but the primary interaction model is an AI
assistant using loghound as a local investigation tool. The raw store stays rich
while the AI sees focused output. See
[doc/product-overview.md](doc/product-overview.md) for the full product
direction.

## Platform support

The first release targets Dart CLI, Flutter mobile, Flutter desktop, and local
development workflows. Flutter Web is not supported yet because the current
transport uses `dart:io`.

## Install

Use loghound as a **dev dependency** when you only need the CLI:

```bash
dart pub add dev:loghound
dart run loghound:loghound serve
```

Use it as a **normal dependency** when app code imports the client SDK:

```bash
dart pub add loghound
```

For a short global command, activate it once:

```bash
dart pub global activate loghound
loghound tail --file loghound/app.jsonl
```

## Quick start

> Uses the activated `loghound` command (`dart pub global activate loghound`);
> otherwise prefix each line with `dart run loghound:loghound`.

Start the receiver in one terminal — host, port, and directory all default:

```bash
loghound stay
```

From another terminal (or your app), send logs. The same commands give an AI
agent enough structure to decide where to inspect next:

```bash
# Send a log — from curl, a script, or the Dart client
curl -X POST http://127.0.0.1:8765/logs -H 'content-type: application/json' \
  -d '{"app_id":"guide-app","flavor":"staging","platform":"ios","session_id":"session-1","name":"Checkout","level":1000,"message":"checkout failed"}'

# Explore — commands default to --root loghound
loghound apps                                    # apps, flavors, sessions
loghound tail --flavor staging                   # recent records across platforms
loghound tail --flavor staging --platform ios
loghound latest-error --flavor staging
```

In a real app, [`LogHound.run`](#flutter-bootstrap) stamps `app_id`, `flavor`,
`platform`, and `session_id` for you. If `flavor` is omitted, routed logs use
`default`; if `platform` is omitted, they use `unknown`. For a single flat file
without routing, use
`serve --out loghound/app.jsonl` and read it with `tail --file …`.

## CLI

> The examples below use `dart run loghound:loghound <command>`. After
> `dart pub global activate loghound`, drop the prefix and call `loghound
> <command>` directly.

### Filter a JSONL file

Use this when an agent needs to inspect a single flat JSONL file:

```bash
dart run loghound:loghound query --file loghound/app.jsonl --contains purchase
dart run loghound:loghound query --file loghound/app.jsonl --name HTTP --since 2026-06-27T10:00:00
dart run loghound:loghound query --file loghound/app.jsonl --trace-id trace-abc
dart run loghound:loghound latest-error --file loghound/app.jsonl
```

`query` filters support `--contains`, `--name`, `--min-level`, `--since`,
`--trace-id`, `--request-id`, `--session-id`, and `--user-id`.

<a id="explore-routed-app-sessions"></a>

### Agent investigation commands

```bash
dart run loghound:loghound apps --root loghound
dart run loghound:loghound sessions --root loghound --flavor staging
dart run loghound:loghound actions --root loghound --flavor staging --platform ios --session session-1
dart run loghound:loghound http list --root loghound --flavor staging --platform ios --session session-1
dart run loghound:loghound http show --root loghound --flavor staging --platform ios --session session-1 --request-id req-1
dart run loghound:loghound body --root loghound --flavor staging --platform ios --session session-1 --request-id req-1 --response --json-path '$.items[0]'
dart run loghound:loghound stats --root loghound --flavor staging
```

These are the commands an AI agent should prefer after `loghound stay` has been
collecting routed app logs. Omit `--platform` to read matching sessions across
iOS, Android, and any other reported platform. `app_id` remains in records and
catalog output; pass `--app` only when you intentionally want to filter by that
metadata.

`http list` prints method, path, status, duration, body sizes, and request IDs.
`http show` prints one call with redacted headers and body metadata. `body`
inspects a stored request or response body with `--json-path`, `--find`, or
`--sample` without dumping unrelated data.

### Build a context bundle

Build a compact Markdown bundle around the latest warning or error:

```bash
dart run loghound:loghound context \
  --file loghound/app.jsonl \
  --latest-error \
  --before 50 \
  --after 20 \
  --max-lines 200 \
  --max-chars 20000
```

`context` includes nearby records and records sharing the latest error's
`trace_id`, `request_id`, `session_id`, or `user_id`. Pass `--format jsonl` for
raw records instead of Markdown.

## Dart client

Use `LogHoundClient` from app or script code when you want logs to flow into the
local receiver:

```dart
import 'package:loghound/loghound.dart';

final logs = LogHoundClient(
  Uri.parse('http://127.0.0.1:8765/logs'),
);

logs.send({
  'timestamp': DateTime.now().toIso8601String(),
  'name': 'Purchase',
  'level': 900,
  'message': 'purchase.guidebook.failed',
  'data': {'productId': 'guidebook.natural_wine'},
});
```

`send` is fire-and-forget. Transport failures are swallowed so development
logging never breaks the app. See [example/client.dart](example/client.dart)
for a complete runnable client, and [example/README.md](example/README.md) for
an overview of every example.

## Flutter bootstrap

For Flutter apps, wrap debug startup once and keep `loghound stay` running:

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

This configures a session, posts `session.start`, captures `print` output,
captures uncaught zone errors, and stamps later events with `app_id`, `flavor`,
`platform`, and `session_id`. It is debug-only by default and silently continues
when `loghound stay` is not running.

`endpoint` is optional. By default, the SDK posts to
`http://127.0.0.1:8765/logs`, or to `LOGHOUND_URL` when provided with
`--dart-define`. For a physical device, pass your Mac's LAN URL with
`--dart-define=LOGHOUND_URL=http://192.168.x.x:8765/logs`.

## HTTP and action capture

Add semantic operation logs where AI should understand user intent:

```dart
LogHound.action('search.submit', data: {
  'query': query,
  'selectedFilters': selectedFilters,
});

LogHound.screen('SpotSearch', route: '/spots/search');
```

Manual HTTP events can be sent today:

```dart
LogHound.http(
  method: 'GET',
  url: '/spots',
  requestId: 'req-1',
  status: 200,
  responseBody: {'items': items},
);
```

HTTP helper bodies are redacted before sending and are capped by default:
request bodies at 64 KB and response bodies at 256 KB. Truncated records keep
`request_body_bytes`, `response_body_bytes`, and `*_body_truncated` metadata.

Automatic Dio/`http` interceptors are the next integration layer; the bootstrap
API is intentionally pure Dart so the CLI package stays lightweight.

## Redaction

Incoming records are redacted before they are written. The default redactor
masks common secret keys such as `authorization`, `cookie`, `password`,
`secret`, `token`, `x-api-key`, and `x-staging-auth`. It also masks common
secret-looking values such as bearer tokens, JWTs, GitHub tokens, AWS access
keys, secret URL query values, and email addresses.

```dart
final redactor = LogHoundRedactor(sensitiveKeys: {'api_key'});
```

Redaction is best-effort and should not be treated as a compliance boundary —
see [SECURITY.md](SECURITY.md).

## JSON Lines and OpenTelemetry

Logs are stored as newline-delimited JSON so they are easy to tail, grep,
filter, inspect, or expose to an AI assistant through small command outputs.

`query`, `latest-error`, and `context` also understand common OpenTelemetry log
fields such as `severity_number`, `severity_text`, `body`, `attributes`,
`trace_id`, and `span_id`.

## AI agent workflow

loghound is intended to be operated by AI agents, with the developer only
starting the receiver and adding app instrumentation. The agent should discover
apps and sessions, read semantic action timelines, inspect HTTP calls by
request ID, and drill into request or response bodies only when needed. The raw
local store can stay rich while the AI sees focused command output.

The planned AI-agent workflow is drafted in
[skills/loghound-investigator/SKILL.md](https://github.com/s-tyd/loghound/blob/master/skills/loghound-investigator/SKILL.md).

## Privacy model

loghound does not upload logs or require an account. The CLI writes local JSONL
files, and the Dart client posts only to the endpoint you configure. The
receiver binds to `127.0.0.1` by default; pass `--host 0.0.0.0` only when you
intentionally want other devices on your network to post logs.

The receiver accepts unauthenticated HTTP `POST` requests. When bound to
`0.0.0.0`, any device that can reach the port can write logs, including large
or malformed records that may consume disk space or slow local inspection.
Use it only on trusted development networks, avoid exposing the port to the
internet, and protect the log directory with normal file permissions. Treat
captured headers, request bodies, response bodies, and user-visible text as
sensitive even when redaction is enabled.

## Roadmap

loghound is pre-1.0; public APIs can still change. Near-term work includes
automatic Dio/`http` body capture, Flutter widget helpers for semantic actions,
stronger redaction policy, and retention/cleanup commands. The full direction
lives in [doc/product-overview.md](doc/product-overview.md), with a current
prioritization snapshot in
[doc/feature-gap-and-competitive-analysis.md](doc/feature-gap-and-competitive-analysis.md).

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) for
the development checks and design direction, and
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for community expectations.

```bash
dart format .
dart analyze
dart test
```

## License

Released under the [MIT License](LICENSE).
