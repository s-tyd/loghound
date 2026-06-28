---
name: loghound-investigator
description: Investigate Flutter or Dart app behavior using local loghound logs and commands. Use when debugging an app session, inspecting API requests or response bodies, understanding what the user did before an error, comparing flavors or sessions, or building AI-ready context from loghound JSONL without dumping entire logs into chat.
---

# loghound investigator

## Overview

Use loghound as a local investigation tool. Do not ask the user to paste whole
log files. Start from app/session metadata, inspect action and HTTP timelines,
drill into request or response bodies only when needed, and produce a compact
debugging explanation with the command evidence used.

## Principles

- Prefer loghound commands over reading raw JSONL directly.
- Treat raw bodies as local evidence, not as content to paste wholesale into the
  final answer.
- Follow IDs: `app_id`, `flavor`, `session_id`, `request_id`, `trace_id`,
  `user_id`, and screen/action names.
- Start broad, then narrow. List apps and sessions before inspecting bodies.
- Redact or omit credentials, tokens, cookies, email addresses, and unrelated
  personal data even if they appear in command output.
- Explain the observed behavior from logged facts, and clearly mark inference.

## Investigation Workflow

1. Check what loghound data exists.

   ```bash
   loghound apps
   loghound sessions --app <app> --flavor <flavor>
   loghound stats --app <app> --flavor <flavor>
   ```

2. Pick the relevant session.

   Use the newest session only if the user did not specify one. Prefer the
   session that contains the reported screen, error, route, request, or flavor.

3. Read the operation timeline before reading bodies.

   ```bash
   loghound actions --app <app> --session <session>
   loghound tail --app <app> --session <session> --count 80
   ```

   Look for semantic operations such as `search.submit`, `item.select`,
   `checkout.confirm`, `screen.view`, `form.validation.failed`, and
   lifecycle/error events.

4. Inspect HTTP calls around the operation or error.

   ```bash
   loghound http list --app <app> --session <session>
   loghound http show --request-id <request-id>
   ```

   Compare method, path, status, duration, request body size, response body
   size, truncation, and correlation IDs.

5. Drill into bodies only after choosing a request.

   ```bash
   loghound body --request-id <request-id> --request --json-path '$'
   loghound body --request-id <request-id> --response --json-path '$.items[0]'
   loghound body --request-id <request-id> --response --find title
   loghound body --request-id <request-id> --response --sample items --count 3
   ```

   Pull the smallest field, object, sample, or search result that answers the
   question. Avoid dumping full arrays or full response bodies.

6. Build compact context when handing off or summarizing.

   ```bash
   loghound context --app <app> --session <session> --latest-error
   loghound context --request-id <request-id> --before 50 --after 20
   ```

   Use context output as a concise bundle. If the bundle points to a
   request ID or body path, inspect that precise target rather than broadening
   immediately.

## Operation Log Expectations

loghound action logs are intended to be semantic and thick enough for AI:

- Use `verb.object` or `domain.intent` names:
  `screen.view`, `search.submit`, `item.select`, `filter.apply`,
  `form.validation.failed`, `purchase.confirm`.
- Include stable identifiers and user-visible labels when safe:
  `screen`, `route`, `itemId`, `title`, `query`, `selectedFilters`,
  `resultCount`, `validationErrors`.
- Include before/after state for meaningful transitions:
  selected tab, sort order, filter set, auth state, feature flag, or form
  validity.
- Connect actions to HTTP by carrying `session_id`, `trace_id`, `request_id`,
  or an operation ID where possible.
- Do not rely on raw tap coordinates as the primary signal. Raw taps can be
  auxiliary, but AI needs intent.

Example action:

```json
{
  "kind": "action",
  "name": "search.submit",
  "screen": "SpotSearch",
  "session_id": "20260627-abc123",
  "operation_id": "op_search_42",
  "data": {
    "query": "ramen",
    "selectedFilters": ["open_now", "nearby"],
    "sort": "distance"
  }
}
```

## Reporting

When reporting findings:

- State the exact session, action, request ID, and body path used.
- Separate observed facts from interpretation.
- Mention missing data explicitly, such as no action logs, no response body, or
  truncated body.
- Recommend the next loghound command only when it would materially reduce
  uncertainty.

Example summary shape:

```text
In session 20260627-abc123, the user submitted search.submit on SpotSearch with
query "ramen". The next GET /spots request req_abc returned 200, but
$.items[1].title was empty and $.items[1].price was null. The later
item.select action used that item ID, then GET /spots/<id> returned 404. This
looks like the list endpoint returned an item that the detail endpoint could not
resolve.
```
