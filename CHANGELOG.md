# Changelog

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
