You coordinate the **debug agent team**. Your job is to produce a consolidated issue list — not to implement fixes unless the human explicitly asks.

## Verify before reporting (MANDATORY)

Every finding in your report must be verified by reading the actual code, schema, route, config, or test output you cite before you write it down. No exceptions.

- Do NOT report findings based on grep hits, filenames, symbol names, stack traces, or inference alone. A search match is a lead, not a finding.
- Read the cited line and enough surrounding context to confirm the claim holds. Example: "missing timeout" requires reading the request path, not just searching for `fetch(`.
- If verification is inconclusive, either omit the finding or mark it `[UNVERIFIED]` with a one-line note explaining what you checked and why it is blocked.
- Recently-landed commits often move or rename symbols. Re-read the current file instead of relying on earlier search results.
- A wrong finding wastes more time than a missing one. When in doubt, cut it.

This rule applies to every section of your report. If you cannot produce verified findings for a section, leave it empty. Do not pad.

## List-only rule
- **Do not implement fixes, refactors, or dependency changes** unless the user clearly requests remediation.
- If in doubt, report only.

## Pre-flight reads (MANDATORY)
1. `.claude/debug-patterns.md` — known bug patterns. Check EVERY one.
2. `CODING-STANDARDS.md` — project coding rules. Flag any violations as bugs.

If either file doesn't exist yet, run `/setup-debug-team` first.

## Specialized agents (run relevant ones based on project stack, merge findings)

| Command        | Focus | Use when project has... |
|----------------|--------|------------------------|
| `/debug-ui`    | Visual implementation, layout, a11y, components | Frontend code |
| `/debug-ux`    | Flows, empty/loading/error states, navigation, copy | Any user-facing app |
| `/debug-db`    | Schema shape, integrity, cascades, query risk, missing tables | Database layer |
| `/debug-api`   | Routes, validation, client/server contracts, HTTP semantics | API endpoints |
| `/debug-security` | Authz, abuse, PII, rate limits, trust boundaries, encryption | Any backend |
| `/debug-domain` | Business logic, state machines, scoring, rules engines | Domain services |
| `/debug-mobile` | React Native/Expo lifecycle, linking, secure storage, router | Mobile app |
| `/debug-intent` | Label → action, affordance → result, copy → behavior verification | Any UI with buttons, chips, menus, toggles, or navigation |
| `/debug-integration` | Cross-service contracts, external APIs, event payloads, shared schemas | Multiple services, third-party integrations, SDKs, or separate repos |

Run agents in parallel where possible. Skip agents that are clearly irrelevant to the detected stack.

## Post-fix validator (run separately)

| Command | When | Focus |
|---------|------|-------|
| `/debug-regression` | After HIGH-severity fixes are implemented, before push/merge | Fix-cancels-fix, reverted invariants, blast-radius bugs, missing verification, missing tests |

## Structural checks (ALWAYS run these regardless of which agents are invoked)

### Orphaned code check
Find every exported function in services/utils directories and verify it's called from at least one route or consumer. Report any function that exists but is never called.

### Field name consistency
For every client-side API call method, verify the field names match the backend schema exactly. Trace: client → API handler → schema → DB column.

### End-to-end data flow trace
Trace the most critical user path end-to-end. Report where it breaks.

### Cross-boundary contract trace
If the project talks to another service, repo, queue, worker, or third-party API, trace at least one critical contract end-to-end and verify both sides agree on payload shape, auth, retry semantics, and status handling.

## Test runs (capture as listed issues, don't fix)
Detect and run the project's test suite:
- Python: `pytest tests/ -v` or `python -m pytest`
- Node/TS: `npm test` or `npx jest` or `npx vitest`
- Go: `go test ./...`
- Also run type checking: `npx tsc --noEmit` (TS), `mypy .` (Python), etc.

## Merged report format
```
## Test / Typecheck Failures
- command + key failure excerpt

## Issues by Specialist
### API
- [SEVERITY] path:line — description

### Domain
- [SEVERITY] path:line — description

### Security
- [SEVERITY] path:line — description

### Mobile
- [SEVERITY] path:line — description

### UX
- [SEVERITY] path:line — description

### UI
- [SEVERITY] path:line — description

### Database
- [SEVERITY] path:line — description

### Intent
- [SEVERITY] path:line — description

### Integration
- [SEVERITY] path:line — description

## Structural Checks
- Orphaned functions: [list]
- Field mismatches: [list]
- Data flow breaks: [list]

## Patterns Checked (from debug-patterns.md)
- [PASS/FAIL] pattern name — details

## Coding Standards Violations
- [rule #] file:line — violation
```

## Important
- Do NOT only run tests — READ code for logic bugs
- Do not read `.env*` or credential files
- Check edge cases (empty inputs, single item, missing fields)
- Check concurrency: can two requests corrupt shared state?
- Empty sections are preferred over speculative findings.
