---
name: integration-test-flow
description: Create, review, or complete integration test flows for PRs, release builds, merge handoffs, debug-only builds, and regression sweeps.
---

# Integration Test Flow

Use this skill when a PR, release, merge handoff, or debug-only build needs a
concrete end-to-end test plan with evidence.

Project docs override this skill on product-specific surfaces, accounts, fixtures,
and deploy markers.

## Procedure

1. **Name the build/stage.** Implementation, debug-only, release candidate, hotfix,
   or docs/tooling-only.
2. **Map touched surfaces.** Start from the diff and architecture docs. Include UI,
   API, jobs, database/RPC, workers, notifications, payments, admin tools, and any
   other side effects the path crosses.
3. **Choose test data.** Name accounts, fixtures, ids, seeded rows, or mock services.
4. **List commands.** Include tests, typecheck, lint, migrations, local servers,
   queue workers, and any validation scripts.
5. **Write manual steps.** Browser/device/API/admin steps should have expected state
   after each major transition.
6. **State expected durable state.** Database rows, admin state, outbound messages,
   logs, background jobs, and final UI/API result.
7. **Attach evidence.** Command output summary, screenshots, log excerpts, request
   ids, row ids, or PR checks.
8. **Handle gaps durably.** If a step cannot run, record blocked step, owner, next
   command, needed evidence, and regression risk in the tracker.

## Debug-Only Builds

Rerun the prior implementation flow, then add targeted regression flows for each
bug fixed in the debug-only build. The regression flow should include:

- pre-fix failure evidence or reproduction,
- the changed path,
- the exact retest command or manual step,
- expected output/state after the fix,
- any adjacent path checked for collateral damage.

## Template

```markdown
## Integration Test Flow

Build type:
Diff base / release marker:
Touched surfaces:
Risk map:

### Accounts / Fixtures
- ...

### Commands
- [ ] `<command>` — expected:

### Manual Flow
1. Step:
   Expected:
   Evidence:

### Durable State
- Database/admin/API/log state:
- Outbound side effects:
- Final UI/API state:

### Regression Checks
- ...

### Blocked Steps / Tracker
- ...

### Result
PASS / FAIL / PARTIAL:
```

## Completion Rules

- Do not leave integration steps only in chat. Put them in the PR body, merge
  handoff, tracker, or committed docs as appropriate.
- If a flow cannot be run, name the owner, next command, and risk.
- Promote repeatable checks into scripts or tests when they are likely to matter
  again.
