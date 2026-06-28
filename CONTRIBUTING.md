# Contributing

Thanks for helping improve loghound.

## Development

Run the standard checks before sending changes:

```bash
dart format .
dart analyze
dart test
dart pub publish --dry-run
```

`dart pub publish --dry-run` should not report package-content warnings. A dirty
git warning is expected only when validating local uncommitted changes.

## Design Direction

loghound is a local investigation harness, not a cloud analytics SDK. Prefer
features that:

- keep raw logs local;
- let humans and AI agents query narrow slices of logs;
- preserve app/flavor/platform/session/request correlation;
- redact secrets before output;
- keep the app running even when loghound is unavailable.

Avoid features that require a hosted account or upload logs by default.

## API Stability

The package is currently pre-1.0. Public APIs can still change, but changes
should be intentional and documented in `CHANGELOG.md`.

## Release Checklist

Before publishing:

- confirm the GitHub repository is public;
- run the standard checks above;
- confirm `.pubignore` excludes local-only assets and agent support files;
- update `CHANGELOG.md`;
- verify README examples match the current API.
