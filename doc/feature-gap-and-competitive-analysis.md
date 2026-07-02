# Feature Gap And Competitive Analysis

This document is a prioritization snapshot for loghound before the first public
release. It is not a product spec by itself. Concrete behavior should still be
designed, tested, and reviewed in the issue or PR that implements it.

The product axis is intentionally narrow:

- Local-first debug investigation.
- Dart and Flutter app sessions.
- AI-agent-operated CLI commands.
- Rich local JSONL storage with thin command outputs.

Hosted observability dashboards, billing, alerts, and central log indexing are
non-goals for the first releases.

## Current Surface

The package already has the foundation for AI-assisted local investigation:

- `loghound stay` reads hidden Dart VM Service extension events and routes them
  by flavor, platform, and session under the app's local log root.
- `LogHound.run` creates a debug-only session, captures `print`, captures zone
  errors, and stamps records with app, flavor, platform, and session metadata.
- Manual `LogHound.action`, `LogHound.screen`, `LogHound.error`, and
  `LogHound.http` calls can emit structured events.
- The CLI can discover apps and sessions, list actions, inspect HTTP calls,
  read selected body paths, compute stats, query records, and build compact
  context bundles.
- Redaction is applied before records are written, with best-effort masking for
  common secret keys and token-like values.

The important gaps are mostly around automation, scale, and agent ergonomics:

- No automatic Dio interceptor.
- No automatic `package:http` wrapper or client.
- No `doctor`, `clean`, `tail --follow`, or `--until` support.
- CLI inspection commands currently materialize matching records before
  sorting and rendering.
- No MCP server or other structured tool surface beyond the CLI.
- No stable error fingerprint or grouping model.
- No documented record schema contract for integrations.

## Competitive Notes

These references are used for shape, not for scope expansion:

- [lnav](https://docs.lnav.org/en/latest/usage.html) reinforces fast local log
  navigation, filtering, and query-like inspection without requiring a hosted
  service.
- [Grafana Loki logcli](https://grafana.com/docs/loki/latest/query/logcli/)
  reinforces label-oriented and time-windowed command-line exploration.
- [Sentry issue grouping](https://docs.sentry.io/concepts/data-management/event-grouping/)
  and breadcrumbs reinforce stable error fingerprints and action timelines.
- [OpenTelemetry OTLP](https://opentelemetry.io/docs/specs/otlp/) is useful as
  an import/export vocabulary, but full collector compatibility is not a first
  release goal.

The parts worth copying are CLI shapes, record fields, and output discipline.
The parts to avoid for now are dashboards, hosted query backends, alerting, and
large operational configuration surfaces.

## Prioritized Backlog

1. `loghound doctor`
   - Diagnose collector availability, writable root, app metadata,
     flavor/platform/session routing, and common setup mistakes.
   - Keep it as a leaf command with no schema changes.

2. `loghound clean --older-than` with `--dry-run`
   - Delete old session files and update catalog/latest behavior safely.
   - Treat routed sessions, legacy flat files, and `latest.jsonl` separately.

3. Time-window query parity
   - Add `--until` to `query`.
   - Add `--since` and `--until` to `tail` for agent-friendly scoped reads.
   - Keep `context` semantics separate; context windows are relation windows,
     not pure time filters.

4. Streaming and early-exit reads
   - Start with `latest-error`, because it has the clearest early-exit value.
   - Add characterization tests before changing output.
   - Use a benchmark or fixture large enough to prove the change matters.

5. `tail --follow`
   - Add live filtered follow after the read primitives are clearer.
   - Keep browser/SSE UI out of scope until CLI follow proves the need.

6. Dio capture
   - Prefer a companion package or optional integration boundary rather than
     adding a hard Dio dependency to the core package.
   - Default to debug-only, body byte limits, truncation metadata, content-type
     filtering, and opt-in body capture controls.

7. MCP server
   - Start with a thin wrapper around `latest-error` and `context`.
   - Do not wait for all streaming work if the initial tool output is bounded.
   - Keep the same local trust boundary as the generated JSONL files.

8. Error fingerprint and grouping
   - Add a stable fingerprint field and grouped `latest-error` output.
   - Keep manual override possible for app-specific grouping.

9. `package:http` integration
   - Implement after Dio exposes the right lifecycle and body-capture API
     choices.

10. Minimal OTLP import
    - Consider only after loghound's own schema is documented.
    - Translate useful log fields into JSONL records; do not become a full
      OpenTelemetry collector.

## Cross-Cutting Requirements

- Record schema documentation should come before new integration packages.
- Security-sensitive features must preserve debug-only defaults and
  best-effort redaction warnings.
- MCP, SSE, or browser tooling must not quietly widen the local trust boundary.
- AI-facing commands should print compact, citeable evidence: app metadata,
  flavor, platform, session, request ID, action name, and body path when
  available.
- Changes to command names, output shape, or investigation order should update
  `skills/loghound-investigator/SKILL.md` at the same time.

## PR Shape

Prefer one independently shippable change per PR:

- Docs and public positioning updates.
- Leaf CLI commands such as `doctor`.
- Retention/cleanup behavior.
- Query option parity.
- Read-path performance work with characterization tests.
- One integration package or wrapper at a time.

This keeps loghound from drifting into a broad observability platform before
the AI-agent investigation loop is excellent.
