# Agent Instructions

When changing LogHound logging coverage, keep implementation, settings, docs,
and tests in sync.

- If a new capture option affects AI investigation quality, add it to
  `LogHoundSettings`, `logHoundSettingDescriptors`, README, and tests in the
  same change.
- HTTP body capture must remain explicit opt-in. Use
  `LOGHOUND_CAPTURE_HTTP_REQUEST_BODY` and
  `LOGHOUND_CAPTURE_HTTP_RESPONSE_BODY` for app-side defaults, and document how
  those values reach Flutter through `--dart-define` or
  `--dart-define-from-file`.
- After changing Dio/HTTP capture behavior, verify `loghound doctor` can detect
  the relevant coverage through `action_records` and `http_body_records`.
- Do not add a runtime-only knob without documenting how an AI agent can
  discover the setting later.
- When publishing a package version, complete the release loop: run verification,
  commit the release changes, publish to pub.dev, and push the release commit to
  the remote branch before reporting completion.
