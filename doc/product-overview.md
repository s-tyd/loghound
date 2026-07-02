# loghound Product Overview

loghound is a local investigation harness for debugging Flutter and Dart apps
with AI assistance. The developer owns setup and instrumentation; the primary
operator of the investigation commands is an AI agent.

The core idea is not to paste an entire log file into an AI assistant.
loghound stores rich raw events locally, then exposes AI-friendly commands for
searching, slicing, and inspecting only the parts needed to debug a problem.

## Core Experience

The developer usually starts the app through loghound:

```bash
loghound run
```

`loghound run` starts `flutter run` and collects hidden `loghound.log`
extension events into `.loghound/`. FVM projects use
`.fvm/flutter_sdk/bin/flutter` automatically. Any VM Service URL plumbing is
internal to loghound.

For split terminals, the developer can keep the collector running separately:

```bash
loghound stay
flutter run
```

Flutter apps use one small debug-only setup:

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

`LogHound.run` emits structured records as Dart VM Service extension events.
`loghound stay` subscribes to the Extension stream, extracts `loghound.log`
events, and routes them to local JSONL files. No LAN address, local HTTP
server, app endpoint configuration, or Flutter log JSON output is required.

The bootstrap emits `session.start`, captures `print`, captures uncaught zone
errors, and stamps `LogHound.action`, `LogHound.screen`, `LogHound.error`, and
`LogHound.http` calls with `app_id`, `flavor`, `platform`, and `session_id`.

## Investigation Model

loghound splits debugging into two layers:

- The raw local store keeps thick data: HTTP bodies, headers after redaction,
  screen transitions, user actions, errors, and diagnostic events.
- The AI-facing commands expose thin views: lists, summaries, filtered slices,
  JSON-path reads, samples, and compact context bundles.

A typical investigation looks like this:

```bash
loghound apps
loghound sessions --flavor staging
loghound http list --flavor staging --platform ios --session 20260627-abc123
loghound http show --flavor staging --platform ios --session 20260627-abc123 --request-id req_abc
loghound body --flavor staging --platform ios --session 20260627-abc123 --request-id req_abc --response --json-path '$.items[1]'
loghound context --flavor staging --platform ios --session 20260627-abc123 --latest-error
```

The first commands answer where to look. The later commands fetch only the
specific body fields, nearby actions, and related errors that explain the
behavior.

## App, Flavor, And Session Routing

Every event should carry routing metadata:

```json
{
  "app_id": "guide-app",
  "flavor": "staging",
  "session_id": "20260627-abc123",
  "device": "ios-simulator",
  "platform": "ios"
}
```

The receiver path is now VM Service `stay`, but the store model remains the same:

```text
.loghound/staging/ios/latest.jsonl
.loghound/staging/ios/sessions/20260627-abc123.jsonl
.loghound/catalog.jsonl
```

The catalog stores session metadata so CLI commands can discover apps, flavors,
platforms, devices, and recent sessions. `app_id` remains available for
filtering and evidence, but it is not part of the primary directory path.

## Captured Timeline

loghound should capture more than HTTP traffic. API data is most useful when it
is connected to user actions and screens.

Example JSONL timeline:

```jsonl
{"kind":"screen","screen":"ProductList","timestamp":"..."}
{"kind":"action","name":"search.submit","data":{"keyword":"wine"}}
{"kind":"http","method":"POST","url":"/search","request_body":{"keyword":"wine"}}
{"kind":"http","method":"GET","url":"/items","response_body":{"items":[{"id":"wine-001","title":"Natural Wine Guide"},{"id":"wine-002","title":""}]}}
{"kind":"action","name":"item.select","data":{"itemId":"wine-002"}}
```

## Privacy Model

loghound has no hosted service. The SDK emits hidden development-only VM
Service events, and the CLI writes local JSONL files. Redaction should happen
before records are emitted and again before AI-facing output is produced.

The design assumes trusted local development machines. Generated JSONL files
can contain real API bodies and user-visible text, so they should be protected
with normal filesystem permissions and never published casually.

## Roadmap

Near-term work should prioritize the hidden collector flow:

1. `loghound stay` ergonomics for Flutter VM Service sessions.
2. Automatic Dio/`http` integration that emits structured `LogHound.http`
   records without hand-written interceptors.
3. Retention and cleanup commands for local JSONL stores.
4. Error fingerprinting and grouping.
5. MCP or editor integrations that query the existing CLI surface without
   expanding the trust boundary.
