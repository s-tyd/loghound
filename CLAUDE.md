# Claude Instructions

When editing LogHound, avoid hidden logging/configuration drift.

- New logging capture behavior must update code, `loghound setting` metadata,
  README usage, and tests together.
- For HTTP body capture, use the standard app-side setting names:
  `LOGHOUND_CAPTURE_HTTP_REQUEST_BODY` and
  `LOGHOUND_CAPTURE_HTTP_RESPONSE_BODY`.
- Keep body capture opt-in because request and response bodies can be large and
  sensitive.
- If a change is meant to improve AI investigation, make sure `loghound doctor`
  or `loghound setting` exposes enough signal for an agent to notice missing
  coverage.
- When publishing a package version, do not stop at pub.dev upload. Run
  verification, commit the release changes, publish, push the release commit to
  the remote branch, and only then report the release as complete.
