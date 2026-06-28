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
- The receiver binds to `127.0.0.1` by default and accepts unauthenticated
  HTTP `POST` requests.
- Use `--host 0.0.0.0` only on trusted development networks. Any device that
  can reach the port can append logs.
- Do not expose the receiver to the internet. Put it behind your local
  firewall or development network boundary.
- Large or malformed log submissions may consume disk space or slow local CLI
  inspection.
- Protect generated JSONL files with normal filesystem permissions.
- `LogHound.run` is debug-only by default. Do not pass `enabled: true` in
  production builds unless you intentionally accept local debug-log capture.
- Treat `LOGHOUND_URL` as development configuration. Do not bake production
  endpoints, shared secrets, or public receiver URLs into released apps.
- If loghound is wrapped by MCP, SSE, browser, or editor tooling, keep those
  tools inside the same trusted local boundary as the receiver.
- Redaction is best-effort and should not be treated as a compliance boundary.
- Avoid publishing generated JSONL logs.
