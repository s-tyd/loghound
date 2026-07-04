# Changelog

## 0.0.5

- Harden `loghound run` isolate resume handling for `--start-paused` Flutter
  runs. LogHound now resumes all paused app isolates visible at VM Service
  connection time, catches PauseStart events without a listener race, and avoids
  force-resuming through DDS when `readyToResume` is available.
- Keep VM Service extension event collection alive when debug stream setup or
  isolate inspection is slow, unavailable, or racing with app shutdown.
- Restore the VM Service event factory test seam when a connector is also
  supplied.

## 0.0.4

- Fix `loghound run` leaving isolates spawned after startup paused when
  `flutter run --start-paused` is used internally. This prevents large Dio JSON
  responses from hanging when Dio decodes them in a worker isolate.

## 0.0.3

- Remove device-specific examples from the README, example docs, and product
  overview. The default setup now shows `loghound run` and `loghound stay`
  without requiring users to think about a specific simulator or device name.

## 0.0.2

- Replace the local HTTP receiver capture path with hidden Dart VM Service
  extension events for debug/profile Flutter sessions.
- Add `loghound run` to start `flutter run`, auto-detect FVM Flutter SDKs,
  collect VM Service events, and write routed JSONL records under `.loghound/`.
- Add `loghound stay` for a background collector that can discover the active
  Flutter VM Service and reconnect across app restarts.
- Remove the old `serve`/receiver-oriented workflow and the related
  `LOGHOUND_URL`, `loghound.env`, and device binding setup.
- Route records to `.loghound/<flavor>/<platform>/sessions/<session_id>.jsonl`,
  `.loghound/<flavor>/<platform>/latest.jsonl`, and `.loghound/catalog.jsonl`.
- Read legacy `loghound/` roots when `.loghound/` does not exist, so existing
  sessions and settings remain discoverable during migration.
- Make `query`, `tail`, `latest-error`, `context`, `actions`, `http`, `body`,
  and `stats` read routed `.loghound/` sessions by default; `--file` now opts
  into a single JSONL file explicitly.
- Keep CLI-side redaction for VM Service collection before records are
  persisted.
- Add `loghound run --flavor` and `--dart-define-from-file` passthrough for
  common Flutter launch setups.
- Add built-in Dio support through `LogHoundDioInterceptor`, with opt-in HTTP
  request/response body capture settings.
- `loghound setting` with no subcommand now prints one structured JSON
  record per setting (key/label/description/type/value/default/command)
  instead of a single flat object; in an interactive terminal it opens a
  navigable list (↑↓ move, space toggles and saves, →/enter expands the
  description, q/Esc quits).
- Add `language` (en/ja) and `context_format` (markdown/jsonl) settings; the
  interactive `loghound setting` list edits enums by cycling with space,
  localizes to the language setting, and colorizes on a capable terminal.
  `loghound context` uses `context_format` as its default when `--format`
  is not given. NDJSON output stays English and uncolored.
- Add `capture_http_request_body` and `capture_http_response_body` settings so
  agents can tell whether HTTP body logging is intentionally enabled.
- Restore non-interactive `loghound setting <key> <value>` writes and reject
  unknown setting keys with a non-zero exit.
- Harden CLI failures for missing Flutter executables, VM Service connection
  errors, malformed settings files, malformed stdin bytes, and interactive
  setting write failures.

## 0.0.1

- Rename package and CLI to loghound.
- Add local HTTP log receiver.
- Add JSON Lines log storage.
- Add AI-friendly `query`, `tail`, and `latest-error` CLI commands.
- Add `context` CLI command for Markdown context around the latest warning/error.
- Add `trace_id`, `request_id`, `session_id`, and `user_id` query filters.
- Add streaming reads for query and latest-error scans.
- Serialize concurrent JSONL appends to preserve valid line boundaries.
- Add OpenTelemetry-style severity support.
- Add fire-and-forget Dart HTTP client.
- Add default redaction for common secret keys and inline header values.
- Add redaction for common secret-looking value patterns.
- Bind the receiver to loopback by default and reject oversized request bodies.
- Document the planned Flutter/API/action observability direction.
- Add `loghound stay` with app/flavor/platform/session routing.
- Add `apps`, `sessions`, `actions`, `http`, `body`, and `stats` CLI commands.
- Add routed directory storage and session catalog support.
- Add `LogHound.run` bootstrap for debug app sessions.
- Add semantic `LogHound.action`, `screen`, `error`, and `http` helpers.
- Show a mascot startup banner on `serve` / `stay` (color on a TTY, honoring `NO_COLOR`).
- Add SDK-side redaction and HTTP body truncation metadata.
- Add timeline summaries to `context` Markdown output.
- Add OSS release docs, GitHub Actions CI, security policy, contributing guide,
  and issue templates.
- Add public API dartdocs, enable `public_member_api_docs`, add an
  `example/README.md`, and update CI to run on `master`.
