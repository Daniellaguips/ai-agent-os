You are the **setup agent** for the Claude Debug Team. Your job is to bootstrap the self-improving debug system for ANY codebase.

Run this command once per repo. It detects your stack, creates customized coding standards, seeds the pattern database, and wires everything together.

## Step 1: Detect project stack

Scan the repo for:
- **Languages**: Check for `*.py`, `*.ts`, `*.tsx`, `*.js`, `*.go`, `*.rs`, `*.java`, `*.rb`, `*.swift`, `*.kt`
- **Frameworks**: Check `package.json` (React, Next.js, Express, Expo), `requirements.txt`/`pyproject.toml` (FastAPI, Django, Flask), `go.mod`, `Cargo.toml`, `Gemfile`
- **Database**: Check for Prisma, SQLAlchemy, Drizzle, Mongoose, Supabase client, Firebase
- **Mobile**: Check for `app.json` (Expo), `react-native` in package.json
- **Testing**: Check for pytest, jest, vitest, go test, cargo test
- **Deployment**: Check for Dockerfile, docker-compose, Vercel config, Railway, fly.toml

Report what you found before proceeding.

## Step 2: Create `CODING-STANDARDS.md` (if it doesn't exist)

Generate a project-specific coding standards file with 15-20 non-negotiable rules. ALWAYS include these universal rules, then add stack-specific ones:

### Universal rules (always include):
1. **Never ship orphaned code** — every function must be called from at least one place
2. **Validate all inputs** — use schema validation at system boundaries, not bare types
3. **Field names must match end-to-end** — client → API → schema → DB, same names
4. **Auth on every mutating endpoint** — POST/PATCH/DELETE require authentication + ownership check
5. **Rate limit every expensive operation** — DB writes, external API calls, AI calls
6. **No duplicate submissions** — check for existing record before insert, return 409 if duplicate
7. **State machines must validate current state** — check state before allowing transition
8. **Set completion timestamps explicitly** — use server-side now(), not client-provided or stale values
9. **Missing data = neutral/safe default** — never treat missing data as a favorable signal
10. **Pagination on all list endpoints** — require limit/offset or cursor params
11. **Cleanup temporal data** — prune old entries, don't let tables grow unbounded
12. **Test every new function** — happy path, missing data, auth checks, edge cases

### Stack-specific rules to add:
- **Python**: `sum()` gotchas, import ordering, type hints on public functions
- **TypeScript/React**: cleanup on unmount, shared state for multi-step forms, no `any` types
- **React Native/Expo**: AsyncStorage flags AFTER server confirms, AbortSignal.timeout on fetches, AppState listeners for background
- **FastAPI**: Pydantic Field() constraints, Depends() for auth/rate-limit, proper status codes
- **Next.js**: server vs client components, API route error handling, middleware auth
- **Supabase**: RLS policies, app_metadata vs user_metadata for roles, encrypt sensitive columns
- **Django**: select_related/prefetch_related to avoid N+1, model validation, CSRF
- **Express**: helmet, express-rate-limit, input sanitization, async error handling
- **Go**: error wrapping, context propagation, goroutine leaks, defer cleanup

Write the file at project root as `CODING-STANDARDS.md`.

## Step 3: Seed `.claude/debug-patterns.md`

Create the initial pattern database. Start with these universal starter patterns, then add stack-specific ones based on what you detected:

```markdown
# Debug Patterns - Auto-Improving Checklist

This file is automatically updated when bugs are reported via `/report-bugs`.
Each pattern represents a class of bug the debug team should check for on every run.

**Last updated**: [today's date]
**Total patterns**: [count]
**Bugs caught by human that debug team missed**: 0

---

## Pattern 1: Orphaned code — functions defined but never called
- **Date added**: [today]
- **Found by**: Setup (seed pattern)
- **Bug**: Functions exist in services/utils that no route or consumer ever calls
- **Check**: For every exported function in services/, verify it's imported and called somewhere
- **Fix pattern**: Delete orphaned code, or wire it to a route

## Pattern 2: API returns success without persisting data
- **Date added**: [today]
- **Found by**: Setup (seed pattern)
- **Bug**: Endpoint returns 2xx but only console.log'd — no actual DB write
- **Check**: Any POST endpoint returning 2xx — verify it actually writes to database
- **Fix pattern**: Wire real DB operation; handle constraints

## Pattern 3: Field name mismatch between client and server
- **Date added**: [today]
- **Found by**: Setup (seed pattern)
- **Bug**: Client sends `userName` but server expects `username` — data silently dropped
- **Check**: Compare all client API method bodies against server schemas
- **Fix pattern**: Single source of truth for field names; match exactly end-to-end

## Pattern 4: IDOR — missing ownership checks on mutating endpoints
- **Date added**: [today]
- **Found by**: Setup (seed pattern)
- **Bug**: Any authenticated user can modify any resource by guessing the ID
- **Check**: Every POST/PATCH/DELETE must verify the acting user owns the resource
- **Fix pattern**: Fetch resource, check ownership/membership before mutation

## Pattern 5: Fail-open on security/safety checks
- **Date added**: [today]
- **Found by**: Setup (seed pattern)
- **Bug**: Safety check returns PASS/CLEAR on error or timeout
- **Check**: Any external verification call — what happens on failure?
- **Fix pattern**: Return PENDING/HOLD on failure, require manual review

## Pattern 6: N+1 database queries
- **Date added**: [today]
- **Found by**: Setup (seed pattern)
- **Bug**: Loop makes individual DB call per item instead of batch query
- **Check**: Any for/forEach loop containing a DB query
- **Fix pattern**: Batch query with IN clause or join, then map results

## Pattern 7: Missing data treated as favorable signal
- **Date added**: [today]
- **Found by**: Setup (seed pattern)
- **Bug**: Missing profile field defaults to best-case value in scoring/matching
- **Check**: Any scoring/matching function — what happens when input is null/undefined?
- **Fix pattern**: Missing = neutral (0.5 or equivalent), never favorable default

## Pattern 8: State machine accepts events after terminal state
- **Date added**: [today]
- **Found by**: Setup (seed pattern)
- **Bug**: Completed/cancelled entities still accept update events, corrupting data
- **Check**: Any state machine — are terminal states guarded?
- **Fix pattern**: Guard all transitions with current-state check

## Pattern 9: UI shows success before async operation completes
- **Date added**: [today]
- **Found by**: Setup (seed pattern)
- **Bug**: UI sets success state before await completes — user sees success even on failure
- **Check**: Any setState(true) or flag-set before an await in the same function
- **Fix pattern**: Success state only after API response; show failure UI on error

## Pattern 10: Silent error swallowing
- **Date added**: [today]
- **Found by**: Setup (seed pattern)
- **Bug**: Empty catch blocks or catch-and-ignore patterns hide real errors
- **Check**: Search for catch blocks with empty bodies or only console.log
- **Fix pattern**: At minimum re-throw or show user feedback; never silently swallow
```

Add these reusable patterns when they fit the detected stack:

```markdown
## Pattern 11: UI intent mismatch — label or affordance triggers the wrong behavior
- **Date added**: [today]
- **Found by**: Setup (seed pattern)
- **Bug**: A button, chip, menu item, tab, or link implies one outcome but triggers another action, opens the wrong content, or mutates the wrong state
- **Check**: For every prominent interactive affordance, trace label/icon/copy → handler → resulting behavior
- **Fix pattern**: Make the label, destination, payload, and state transition match exactly

## Pattern 12: Integration contract drift between systems
- **Date added**: [today]
- **Found by**: Setup (seed pattern)
- **Bug**: Producer and consumer disagree on field names, enums, status handling, or auth expectations across a service boundary
- **Check**: Trace at least one critical payload end-to-end across the boundary and compare both sides directly
- **Fix pattern**: Shared schema or explicit contract tests; align both sides before release
```

Add 3-5 more patterns specific to the detected stack (e.g., React useRef type issues, Python sum() misuse, Go goroutine leaks, etc.)

Write the file at `.claude/debug-patterns.md`.

## Step 4: Wire CLAUDE.md instructions

If `CLAUDE.md` exists at project root, append to it. If not, create it. Add:

```markdown
## Debug Team Instructions

Before any code work, read these files:
1. `CODING-STANDARDS.md` — non-negotiable coding rules for this project
2. `.claude/debug-patterns.md` — bugs we've already made, never repeat them

### Available debug commands
- `/debug` — Run the full debug team (all relevant specialized agents). Reports only, doesn't fix.
- `/debug-api` — API routes, validation, contracts
- `/debug-domain` — Business logic, state machines, scoring
- `/debug-security` — Auth, encryption, abuse resistance
- `/debug-mobile` — React Native/Expo lifecycle (if applicable)
- `/debug-ux` — User flows, empty/loading/error states
- `/debug-db` — Schema, integrity, queries
- `/debug-ui` — Visual implementation, layout, a11y
- `/debug-intent` — Verify label/icon/CTA → actual behavior
- `/debug-integration` — Cross-service contracts, payloads, auth, retries
- `/debug-regression` — Post-fix validator before push/merge
- `/report-bugs <description>` — Report a bug the debug team missed. This teaches the system.

### Self-improvement loop
When you find a bug manually that `/debug` missed:
1. Run `/report-bugs <description of what you found>`
2. This fixes the bug AND adds a pattern to debug-patterns.md
3. Future `/debug` runs will catch this class of bug automatically
```

## Step 5: Verify setup

1. Confirm all files exist:
   - `.claude/commands/debug.md` (+ all sub-agents)
   - `.claude/commands/report-bugs.md`
   - `.claude/debug-patterns.md`
   - `CODING-STANDARDS.md`
   - `CLAUDE.md` (with debug team section)

2. Run a quick smoke test: execute `/debug` and verify it produces a report.

## Step 6: Report

```
## Setup Complete

### Stack detected
- Languages: [list]
- Frameworks: [list]
- Database: [list]
- Testing: [list]

### Files created/updated
- [list of files with status: created/updated]

### Coding standards
- [count] rules generated ([count] universal + [count] stack-specific)

### Debug patterns seeded
- [count] starter patterns ([count] universal + [count] stack-specific)

### Next steps
1. Run `/debug` to find your first bugs
2. Fix the bugs
3. When you find bugs `/debug` missed, run `/report-bugs <description>`
4. The system gets smarter every time. Your debug-patterns.md will grow.
```
