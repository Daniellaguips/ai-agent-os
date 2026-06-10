# Debug Agent Team

A self-improving team of specialized debug agents for Claude Code. Drop into any
repo, run `/setup-debug-team`, and get an automated QA team that gets smarter every
time it misses a bug.

## What is this?

Specialized debug agents that run in parallel to find bugs in your codebase:

| Agent | What it catches |
|-------|----------------|
| `/debug-api` | Bad HTTP semantics, unvalidated input, missing auth, field name mismatches |
| `/debug-domain` | Business logic bugs, state machine errors, scoring edge cases |
| `/debug-security` | IDOR, fail-open checks, missing encryption, rate limit gaps |
| `/debug-mobile` | RN/Expo lifecycle leaks, async flag timing, cleanup on unmount |
| `/debug-ux` | Dead-end flows, missing loading/error states, double-submit |
| `/debug-db` | N+1 queries, missing indexes, enum drift, nullable mismatches |
| `/debug-ui` | Layout breaks, a11y gaps, dead UI code, contrast issues |
| `/debug-intent` | Label/action mismatches, wrong destinations, product intent gaps |
| `/debug-integration` | Cross-service contracts, event payloads, auth and retry drift |
| `/debug-regression` | Post-fix validation, blast radius, missing retests |

Run them all at once with `/debug`, or individually.

## The self-improving loop

This is the key differentiator. When you find a bug the debug team missed:

```
/report-bugs "the checkout crashes when the cart is empty"
```

This does 4 things:
1. Fixes the specific bug
2. Generalizes it into a pattern ("array operation without empty-check")
3. Searches the entire codebase for other instances of the same pattern
4. Adds the pattern to `debug-patterns.md` so `/debug` catches it forever

Your `debug-patterns.md` starts with 10-15 seed patterns and **grows automatically**. After a few weeks of use, you'll have 50+ patterns specific to YOUR codebase and YOUR team's blind spots.

## Setup (2 minutes)

### 1. Copy the command files into your repo

```bash
# From this bundled agents/ directory
cp -r .claude/ /path/to/your/repo/.claude/
```

### 2. Run the setup agent

Open Claude Code in your repo and run:

```
/setup-debug-team
```

This will:
- Detect your tech stack (Python, TS, Go, React Native, etc.)
- Generate `CODING-STANDARDS.md` customized to your stack
- Seed `debug-patterns.md` with starter patterns + stack-specific ones
- Wire `CLAUDE.md` so Claude always reads your standards before coding

### 3. Run your first debug sweep

```
/debug
```

You'll get a consolidated report of every bug found, grouped by area and severity.

## Usage

### Full sweep (recommended)
```
/debug
```
Runs all relevant specialists, structural checks, and test suites. Reports only —
doesn't auto-fix.

### Single agent
```
/debug-security
```
Run one agent when you want to focus on a specific area.

### Report a missed bug
```
/report-bugs "description of what you found"
```
Teaches the system. This is how it gets smarter.

### Fix bugs after a sweep
After reviewing the `/debug` report, tell Claude:
```
"implement fixes"
```
It will fix the reported issues, run tests, and commit.

## How it works

```
                    You find a bug manually
                            |
                            v
                    /report-bugs "..."
                            |
                    +-------+-------+
                    |               |
                    v               v
            Fix the bug     Add pattern to
                         debug-patterns.md
                                |
                                v
                    Next /debug run checks
                    this pattern automatically
                                |
                                v
                    Catches this bug class
                    across entire codebase
                            |
                            v
                    System gets smarter
                    (repeat forever)
```

## File structure

```
your-repo/
  .claude/
    commands/
      debug.md              # Coordinator — runs all agents
      debug-api.md           # API routes, validation, contracts
      debug-domain.md        # Business logic, state machines
      debug-security.md      # Auth, encryption, abuse resistance
      debug-mobile.md        # React Native/Expo lifecycle
      debug-ux.md            # User flows, states
      debug-db.md            # Schema, queries, integrity
      debug-ui.md            # Visual implementation, a11y
      debug-intent.md        # Label/action and product intent checks
      debug-integration.md   # Cross-service contract checks
      debug-regression.md    # Post-fix regression checks
      report-bugs.md         # Self-improvement feedback loop
      setup-debug-team.md    # One-time setup agent
    debug-patterns.md        # Auto-growing pattern database
  CODING-STANDARDS.md        # Project-specific coding rules
  CLAUDE.md                  # Claude Code project instructions
```

## Customization

### Adding your own agents

Create a new `.claude/commands/debug-<name>.md` following the same structure:
1. Scope (what files/areas to check)
2. "Read first" section pointing to debug-patterns.md and CODING-STANDARDS.md
3. Checklist of specific things to look for
4. Report format

Then add it to the table in `debug.md`.

### Adding patterns manually

Edit `.claude/debug-patterns.md` and add entries following the existing format. Each pattern needs:
- Description of the bug class
- A generalizable check (regex, code pattern, or logic rule)
- The fix pattern

## FAQ

**Q: Does this work with any language/framework?**
A: Yes. The setup agent detects your stack and customizes accordingly. The core patterns (IDOR, N+1, orphaned code, etc.) are universal.

**Q: How many patterns should I expect after a month?**
A: Active projects typically reach 30-50 patterns. Each one represents a class of bug your team will never ship again.

**Q: Can I share patterns between repos?**
A: Yes — copy `debug-patterns.md` between repos. Universal patterns transfer directly. Stack-specific ones transfer to repos with the same stack.

**Q: Does it modify my code?**
A: `/debug` only reports. It never auto-fixes unless you explicitly ask. `/report-bugs` fixes the specific bug you reported and adds a pattern.
