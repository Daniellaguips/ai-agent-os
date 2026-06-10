---
name: design-consensus
description: Run a panel of senior product/brand designers that review screenshots, score visual design, and converge on a prioritized set of build-ready changes. Use when asked to rate a design, improve a page visually, run a design review/consensus, or critique layout, hierarchy, color, typography, imagery, spacing, responsiveness, and polish. Reusable across projects.
---

# design-consensus

Multi-designer consensus review for visual product work. This is distinct from
copy review: it judges layout, hierarchy, color, typography, imagery, spacing,
responsiveness, and polish.

## Before running
1. Capture durable screenshots the reviewers can see: desktop and a narrow mobile
   viewport, saved to a stable path. Use the available browser tool for the
   environment and follow the hub browser-lease rules when using a shared persistent
   browser profile.
2. Read the project brand canon (`docs/brand/BRAND-CANON.md`, `BRAND.md`, design
   tokens, or equivalent) and pass the visual identity constraints into every review.
   Provide a textual ground-truth description as fallback if image rendering is weak.

## Workflow

Assess with 5 distinct lenses when the task is substantial; use 3 for a small page or
component:
- layout and hierarchy
- color and type
- responsive/mobile UI
- art direction and imagery
- polish and design-system consistency

Each reviewer scores 1-100 and lists 4-8 build-ready improvements with title, change,
rationale, severity, and affected area.

Converge by pooling and deduping items, then keep the changes a majority of reviewers
would still make after seeing the pool. For high-stakes work, run another vote round;
stop when the accepted set is stable or the requested timebox is reached.

Improve by compiling the accepted set into ordered before/after changes and concrete
implementation notes that reuse the project's existing classes, components, tokens,
and CSS variables.

## Honesty

Report the real agreement level and majority-accepted set. Do not imply unanimity if
the panel did not reach it. Surface decisions that need founder/product direction,
such as palette forks or brand-positioning tradeoffs, rather than silently choosing.
