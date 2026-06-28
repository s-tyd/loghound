# loghound Product Overview

loghound is a local investigation harness for debugging Flutter and Dart apps
with AI assistance. The developer owns setup and instrumentation; the primary
operator of the investigation commands is an AI agent. Its long-term direction
is to capture the app session timeline: user actions, screens, API requests and
responses, errors, and real response data.

The core idea is not to paste an entire log file into an AI assistant. loghound
should store rich raw events locally, then expose AI-friendly commands for
searching, slicing, and inspecting only the parts needed to debug a problem.
The AI assistant should be able to use loghound as a tool: start from apps and
sessions, inspect HTTP calls, drill into a response body with a JSON path, and
build a compact context bundle only after it knows what matters.

This document describes the planned product direction. The current package
already provides the local receiver, `stay`, flavor/platform/session routing,
JSONL storage, redaction, filtering, `apps`, `sessions`, `actions`,
`http`, `body`, `stats`, AI-friendly context commands, and the pure-Dart
`LogHound.run` bootstrap. Automatic Dio/http capture and automatic
Flutter widget action capture are planned integration layers.

## Core Experience

The developer starts loghound once:

```bash
loghound stay
```

`stay` is the local receiver that waits for debug apps, receives structured
logs, and routes them by flavor, platform, and session. The name matches loghound's
theme: the local hound stays and waits for app events.

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

If `loghound stay` is running, events are sent automatically. If it is not
running, the app continues normally and failed sends are swallowed after a
short timeout.

The current bootstrap posts `session.start`, captures `print`, captures
uncaught zone errors, and stamps `LogHound.action`, `LogHound.screen`,
`LogHound.error`, and `LogHound.http` calls with `app_id`, `flavor`,
`platform`, and `session_id`. The planned Flutter/Dio integrations should make
HTTP and widget actions automatic on top of this bootstrap.

## Investigation Model

loghound should split debugging into two layers:

- The raw local store keeps thick data: HTTP bodies, headers after redaction,
  screen transitions, user actions, errors, and diagnostic events.
- The AI-facing commands expose thin views: lists, summaries, filtered slices,
  JSON-path reads, samples, and compact context bundles.

This keeps the useful data available without forcing every body and every log
line into the AI context window. A typical investigation should look like this:

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
behavior. `context` should be a bounded evidence bundle, not the only way an AI
assistant can access logs.

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

The receiver keeps `app_id` as metadata, but uses the app's local log root as
the app boundary. It routes logs without requiring the developer to change
output paths when switching flavors:

```text
loghound/staging/ios/latest.jsonl
loghound/staging/ios/sessions/20260627-abc123.jsonl
loghound/catalog.jsonl
```

The catalog stores session metadata so CLI commands can discover apps, flavors,
platforms, devices, and recent sessions. `app_id` remains available for
filtering and evidence, but it is not part of the directory path. When flavor
is not supplied, the route uses `default`; when platform is not supplied, the
route uses `unknown`.

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
{"kind":"http","method":"GET","url":"/items/wine-002","status":404}
```

This timeline gives loghound enough structure for an AI assistant to explore
what the user did and what data the app received. The assistant can reason from
real observed data instead of a schema or a hand-written summary.

## HTTP Body Capture

HTTP capture should focus on debug API understanding. In debug builds, JSON and
text bodies are valuable enough to capture locally by default when the developer
opts into HTTP capture, because the real response often explains the bug.

- Request method, URL, status, and duration.
- Request JSON body.
- Response JSON body, including real item fields and values.
- Response truncation metadata when the body is large.
- Body byte counts and hashes, so large responses can be identified without
  printing them.
- Content-type filtering so binary data, images, PDFs, and large downloads are
  not stored by default.
- Route-level and session-level controls for temporarily capturing larger
  bodies during a focused investigation.

Example event:

```json
{
  "kind": "http",
  "request_id": "req_abc",
  "method": "GET",
  "url": "https://api.example.com/items",
  "status": 200,
  "duration_ms": 182,
  "response_body_bytes": 1842,
  "response_body_truncated": false,
  "response_body": {
    "items": [
      {"id": "wine-001", "title": "Natural Wine Guide", "price": 1200},
      {"id": "wine-002", "title": "", "price": null}
    ]
  }
}
```

The point is not just to know that `GET /items` returned 200. The point is to
let AI see that `items[1].title` is empty and `items[1].price` is null.

Bodies should not be copied wholesale into AI context by default. The raw store
keeps them; commands such as `body --json-path`, `body --find`, and
`body --sample` expose the relevant slice when the developer or AI assistant
asks for it.

## Action Capture

Action capture should be semantic and rich enough for AI to reconstruct what
the user intended. Raw tap-coordinate logging is noisy and often does not help
AI understand intent. loghound should prefer operation logs: named events with
screen, route, stable IDs, visible labels, input values, selected filters,
before/after state, and correlation IDs.

Meaningful actions can be captured with small annotations:

```dart
LogHound.action('item.select', {
  'itemId': item.id,
  'title': item.title,
  'source': 'search_results',
});
```

Widget helpers can reduce repeated code:

```dart
LogHoundTap(
  name: 'purchase.tap',
  data: {'productId': product.id},
  child: ElevatedButton(...),
);
```

Default action capture should include lifecycle, route changes, screen names,
errors, and manual actions. Raw tap capture should remain opt-in and auxiliary.

Example rich operation event:

```json
{
  "kind": "action",
  "name": "search.submit",
  "screen": "SpotSearch",
  "route": "/spots/search",
  "operation_id": "op_search_42",
  "data": {
    "query": "ramen",
    "selectedFilters": ["open_now", "nearby"],
    "sort": "distance"
  }
}
```

This lets an AI assistant connect intent to network behavior:

```text
Action: search.submit query=ramen filters=[open_now, nearby]
HTTP: GET /spots?query=ramen -> 200 request_id=req_abc
Body: $.items[1].title == ""
Action: item.select itemId=spot_002 source=search_results
HTTP: GET /spots/spot_002 -> 404 request_id=req_def
```

The action event should be thick enough that the assistant can answer "what was
the user trying to do?" before it inspects HTTP bodies.

## Redaction And Safety

Because loghound stores real debug data, redaction must be on by default.
Redaction should happen in multiple layers:

1. SDK redaction before sending to `stay`.
2. Receiver redaction before writing JSONL.
3. Context redaction before printing AI-ready output.

Sensitive headers and values should be masked automatically:

- `authorization`
- `cookie`
- `set-cookie`
- `x-api-key`
- `api-key`
- `x-access-token`
- `x-refresh-token`
- `csrf-token`
- `x-csrf-token`
- `password`
- `secret`
- `token`
- Bearer tokens
- JWT-like values
- GitHub tokens
- AWS access keys
- URL query values such as `access_token`, `api_key`, and `token`
- Email addresses

Headers should default to safe capture only:

```text
content-type
accept
accept-language
user-agent
x-request-id
x-correlation-id
```

Developers can opt into redacted-all header capture when they need to inspect
which headers are present without exposing credentials.

## CLI Direction

The CLI should let AI agents navigate by flavor, platform, and session instead
of asking developers to find file paths. The current implementation
includes these commands:

```bash
loghound apps
loghound sessions --flavor staging
loghound tail --flavor staging
loghound context --flavor staging --latest-error
```

For AI-driven investigation, the CLI should also expose structured commands
around HTTP and actions. The current implementation includes the first version
of these commands:

```bash
loghound http list --flavor staging --platform ios --session 20260627-abc123
loghound http show --flavor staging --platform ios --session 20260627-abc123 --request-id req_abc
loghound body --flavor staging --platform ios --session 20260627-abc123 --request-id req_abc --response --json-path '$.items[1]'
loghound body --flavor staging --platform ios --session 20260627-abc123 --request-id req_abc --response --find title
loghound actions --flavor staging --platform ios --session 20260627-abc123
loghound stats --flavor staging
```

`http list` should print method, path, status, duration, body sizes, and
request IDs. `http show` should print one call with redacted headers and body
metadata. `body` should inspect a stored request or response body without
dumping unrelated data. `stats` should make log volume, largest bodies,
truncation, and redaction counts visible.

`context` should prioritize the useful timeline around failures:

```text
Screen: ProductList
Action: search.submit {"keyword":"wine"}
HTTP: POST /search -> 200
HTTP: GET /items -> 200
Response: items[1].title == ""
Action: item.select {"itemId":"wine-002"}
HTTP: GET /items/wine-002 -> 404
```

This output is meant to be a compact starting point for an AI assistant. If the
assistant needs more detail, it should use loghound commands to inspect the
specific request, body field, action, or session instead of asking the
developer for the entire log file.

## AI Agent Skill

loghound should ship with an AI-agent skill that teaches assistants how to
investigate local logs without loading everything into chat. The initial skill
draft lives at `skills/loghound-investigator/SKILL.md`.

The skill should guide an assistant to:

- Discover apps, flavors, and sessions first.
- Read semantic action timelines before opening response bodies.
- Inspect HTTP calls by request ID.
- Use body commands with JSON paths, search, or samples.
- Treat full bodies as local evidence, not default context.
- Report the exact session, action, request ID, and body path behind a finding.
- Keep redaction discipline even when raw logs contain secrets.

This matters because loghound's best experience is interactive. The assistant
should ask loghound precise questions, not ask the developer to paste a giant
JSONL file.

## Implementation Order

Completed foundation:

1. Add `--flavor`, `--platform`, and `--session` route filters to existing CLI
   commands, with optional `--app` metadata filtering.
2. Add `loghound stay` as the local flavor/platform/session-aware receiver.
3. Add routing and `catalog.jsonl`.
4. Add `apps` and `sessions` commands.
5. Add `actions`, `stats`, `http list`, `http show`, and `body` exploration
   commands.
6. Add the `loghound-investigator` AI skill draft.
7. Add the pure-Dart `LogHound.run` bootstrap with session metadata,
   print capture, zone error capture, and manual semantic event helpers.

Next implementation steps are tracked as a prioritization snapshot in
[feature-gap-and-competitive-analysis.md](feature-gap-and-competitive-analysis.md).
The near-term direction is:

1. Add leaf CLI commands such as `doctor` and safe `clean --older-than`
   support.
2. Add time-window parity with `--until` and scoped `tail` reads.
3. Characterize and improve hot read paths before changing large-log behavior.
4. Add automatic HTTP capture through optional integration boundaries.
5. Add a thin MCP/tool surface for the most useful agent queries.

## Positioning

loghound should become a local, AI-friendly debug investigation harness. It is
not just a logger, not a cloud analytics service, and not a tool that blindly
dumps entire logs into chat. It should help developers and AI assistants answer:

- What did the user do?
- Which screen were they on?
- What API request did the app send?
- What did the API actually return?
- Which real fields were empty, null, missing, or unexpected?
- Which error happened next?

The value is the complete local timeline from user action to API data to error,
plus commands that let AI-assisted debugging explore that timeline one precise
question at a time.
