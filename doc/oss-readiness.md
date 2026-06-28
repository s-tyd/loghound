# OSS Readiness

This checklist tracks items that matter before the first public release.

## Current Release Blockers

- GitHub repository visibility is currently `PRIVATE`. Make
  `https://github.com/s-tyd/loghound` public before publishing to pub.dev.
- GitHub Discussions is referenced from issue template contact links. Enable
  Discussions before public release or remove that contact link.
- Security reporting must have a concrete private route: GitHub security
  advisories enabled, or a maintainer contact that can receive reports.
- README public links should be rechecked after the repository is public and
  after the release tag is created, especially raw GitHub image links and the
  AI-agent skill link.

## Package Hygiene

- `.pubignore` excludes local-only `docs/superpowers/`, `skills/`,
  generated `loghound/` and `logs/`, and `loghound-icon.png`.
- `skills/loghound-investigator/` should stay in GitHub for AI-agent workflows,
  but should not ship in the pub runtime package.
- `doc/product-overview.md` is intended to ship with pub package docs.
- `doc/feature-gap-and-competitive-analysis.md` is intended to ship with pub
  package docs as a public roadmap snapshot.
- `doc/oss-readiness.md` is an internal release checklist and should not ship.
- `docs/superpowers/` is internal planning context and should not ship.
- `loghound-icon.png` is a local working asset at the repository root. It is
  ignored by Git and excluded from pub packages.

## Platform Support

The initial SDK uses `dart:io` through `LogHoundClient`, so the first release
targets Dart CLI, Flutter mobile, Flutter desktop, and local development
workflows. Flutter Web is not supported yet.

If Web support becomes a goal, add a separate browser transport using
conditional imports rather than weakening the CLI/server package.

## Roadmap Snapshot

Feature gaps are tracked as roadmap items, not first-publish blockers. See
[feature-gap-and-competitive-analysis.md](feature-gap-and-competitive-analysis.md)
for prioritization and competitive notes.

Near-term candidates:

- `loghound doctor` for receiver, port, and package setup checks.
- Safe retention and cleanup commands such as `loghound clean --older-than`.
- Query and tail time-window parity, including `--until`.
- Characterized read-path improvements for large JSONL files.
- Optional Dio and `package:http` integrations without bloating the core
  package.
- A thin MCP/tool surface for agent-driven investigation.

## Maintenance Items

- `lib/src/cli.dart` is now large because it contains command parsing,
  routing, HTTP/body helpers, stats, and context rendering. It is acceptable for
  the first publish while behavior is still moving, but should be split before
  1.0 into focused command modules and formatter helpers.

## Release Checks

Run:

```bash
git status --short
dart format --set-exit-if-changed .
dart analyze
dart test
dart pub publish --dry-run
```

Expected before publish:

- Worktree is clean.
- Dry-run has no package validation warnings.
- Package contents do not include generated `loghound/` or `logs/`, internal
  `.vimana/` context, `skills/`, `docs/superpowers/`, or local working assets.
- Public README links resolve from pub.dev and GitHub.
