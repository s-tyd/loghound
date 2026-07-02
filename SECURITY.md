# Security Policy

loghound is intended for local development logs. It can contain real API
responses and user-visible data, so treat generated log files as sensitive.

## Supported Versions

Security fixes are handled on the latest published version.

## Reporting A Vulnerability

Please report security issues privately by opening a GitHub security advisory
for the repository, or by contacting the maintainer directly if advisories are
not available.

Do not include tokens, credentials, production log files, or private API
responses in public issues.

## Data Handling Expectations

- loghound does not upload logs to a cloud service.
- The SDK emits structured `loghound.log` records through Dart VM Service
  extension events in debug/profile sessions.
- `loghound stay` subscribes to those events and writes local JSONL files.
- Protect generated JSONL files with normal filesystem permissions.
- `LogHound.run` is debug-only by default. Do not pass `enabled: true` in
  production builds unless you intentionally accept local debug-log capture.
- Avoid publishing generated JSONL logs.
- Redaction is best-effort and should not be treated as a compliance boundary.
- If loghound is wrapped by MCP, browser, editor, or shell tooling, keep those
  tools inside the same trusted local development boundary as the log files.
