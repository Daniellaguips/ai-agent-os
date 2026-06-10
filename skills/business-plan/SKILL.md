---
name: business-plan
description: "Use this skill when the user asks to create a business plan, pitch deck, partnership proposal, or financial model for any business idea in any industry. Triggers on: 'create a business plan', 'make a pitch deck', 'business proposal for', 'financial model for', 'partnership proposal', 'help me plan a business', 'business plan for a [type of business]', '/business-plan'. Produces professional deliverables (docx, xlsx, pptx) using a multi-agent research and review pipeline."
---

# Multi-Agent Business Plan Generator

Create comprehensive, investor/partner-ready business plans for any business idea in any sector. The skill deploys a team of specialized AI agents that research, draft, critique, align, and produce professional deliverables.

Suggested invocation arguments: `<business-description> [--sector <industry>] [--location <city/state>]`.

## How It Works

A team of agents collaborates in phases:

**Phase 1 — Paired Research (6 agents, 3 pairs)**
Each research area gets a Lead + Challenger pair. The Lead drafts, the Challenger critiques, then the Lead incorporates feedback.

- **Pair 1: Market Research** — Demographics, competition, pricing benchmarks, addressable market, target segments
- **Pair 2: Operations & Logistics** — How the business runs day-to-day, equipment, staffing, technology, legal/insurance
- **Pair 3: Brand & Marketing** — Naming, positioning, go-to-market, launch timeline, channels, community strategy

**Phase 1.5 — Cross-Team Sync (3 alignment conversations)**
Lead agents from each pair meet pairwise to ensure their work is consistent and aligned before financials.

**Phase 2 — Financial Modeling (1 agent)**
Reads all aligned briefs and builds revenue models, cost projections, break-even analysis, sensitivity analysis, and year-1 monthly P&L.

**Phase 3 — Document Creation (3 agents in parallel)**
- Business Plan Writer → `.docx`
- Spreadsheet Builder → `.xlsx`
- Pitch Deck Creator → `.pptx`

**Phase 4 — QA Review (1 agent)**
Senior reviewer reads all 3 deliverables, checks number consistency, flags errors, and produces a fix list.

**Phase 5 — Final Revisions**
Apply all QA fixes and regenerate clean files.

## Industry Specialist Agent

One agent in each pair automatically transforms into a **domain specialist** for the business sector. For example:
- Restaurant → food service regulations, health codes, kitchen equipment, food cost ratios
- SaaS → MRR/ARR metrics, churn modeling, CAC/LTV, cloud infrastructure costs
- Retail → foot traffic analysis, inventory management, POS systems, seasonal patterns
- Real estate → zoning, licensing, commission structures, MLS access
- Healthcare → HIPAA compliance, credentialing, insurance billing, malpractice

The specialist agent is always Agent 2A (Operations Lead), because operations vary the most by industry. This agent receives extra instructions to research industry-specific regulations, typical cost structures, required licenses, and operational norms for the target sector.

## Execution Flow

### Step 1: Gather Requirements
Before launching agents, collect from the user (use AskUserQuestion if not provided):
- **Business concept** — What is the business?
- **Location** — City/state/country (affects demographics, regulations, competition)
- **Investment level** — Budget range or "recommend tiers"
- **Revenue model preference** — Fixed pricing, subscription, commission, marketplace, etc.
- **Target customer** — Who is this for?
- **Unique angle** — What makes this different?
- **Output format** — Always produce all 3 (docx + xlsx + pptx) unless told otherwise

### Step 2: Create Briefs Directory
```
mkdir -p "<project-dir>/briefs"
```

### Step 3: Launch Phase 1 — Three Lead Agents (parallel)

Launch 3 agents using the Agent tool with `run_in_background: true`:

**Agent 1A — Market Research Lead:**
Prompt template (adapt sector/location):
```
You are the Market Research Lead for a business plan to [BUSINESS CONCEPT] in [LOCATION].
Research: local demographics, competition within [RADIUS], pricing benchmarks,
target customer segments, addressable market sizing, market gaps.
Use WebSearch extensively. Save to: <dir>/briefs/market_research_v1.md
```

**Agent 2A — Operations Lead (INDUSTRY SPECIALIST):**
```
You are the Operations Lead AND [INDUSTRY] specialist for [BUSINESS CONCEPT] in [LOCATION].
You have deep expertise in [INDUSTRY] operations. Research:
- Industry-specific regulations and licenses for [LOCATION]
- Typical cost structures and margins in [INDUSTRY]
- Required equipment, technology, staffing
- Daily operations workflow
- Insurance and liability specific to [INDUSTRY]
- Membership/pricing models common in [INDUSTRY]
- [Any sector-specific items]
Use WebSearch for current regulations and costs. Save to: <dir>/briefs/operations_v1.md
```

**Agent 3A — Brand & Marketing Lead:**
```
You are the Brand & Marketing Lead for [BUSINESS CONCEPT] in [LOCATION].
Research: brand naming (5-7 options), value proposition, go-to-market strategy,
marketing channels appropriate for [LOCATION SIZE], launch timeline, budget.
Save to: <dir>/briefs/brand_marketing_v1.md
```

### Step 4: Launch Phase 1 — Three Challenger Agents (parallel, after leads finish)

Each challenger reads the corresponding v1 brief and writes a critique:
- Agent 1B → `market_research_critique.md`
- Agent 2B → `operations_critique.md`
- Agent 3B → `brand_marketing_critique.md`

### Step 5: Leads Incorporate Feedback (parallel)
Each lead reads their critique and produces a final brief:
- `market_research_final.md`
- `operations_final.md`
- `brand_marketing_final.md`

### Step 6: Cross-Team Sync (parallel)
3 sync agents check alignment between pairs:
- Market ↔ Operations → `sync_market_operations.md`
- Market ↔ Brand → `sync_market_brand.md`
- Operations ↔ Brand → `sync_operations_brand.md`

### Step 7: Financial Modeling
1 agent reads all finals + syncs, produces `financial_model.md` with:
- Startup costs (tiered)
- Monthly operating costs
- Revenue scenarios (conservative/moderate/optimistic)
- Break-even analysis
- Year-1 monthly P&L
- Sensitivity analysis

### Step 8: Document Generation (parallel)
3 agents write Python scripts using `python-docx`, `openpyxl`, `python-pptx`:
- Business Plan → `[Name]_Business_Plan.docx`
- Financials → `[Name]_Financials.xlsx`
- Pitch Deck → `[Name]_Pitch_Deck.pptx`

Design specs:
- Color scheme: dark navy (#1F4E79) + warm accent color appropriate to the brand
- Professional fonts (Arial/Calibri), consistent sizing
- Tables for financial data with formatted headers
- Pitch deck: 13-15 slides, widescreen, clean visual hierarchy

### Step 9: QA Review
1 agent reads all 3 deliverables + source briefs, checks:
- Number consistency across documents
- Factual accuracy
- Professional quality
- Missing elements
- Produces specific fix list

### Step 10: Apply Fixes and Regenerate
Fix all issues identified by QA, regenerate all 3 files.

## Deliverables

Every run produces:
1. **Business Plan (.docx)** — Executive summary, market analysis, operations, financials, risk analysis, partnership terms
2. **Financial Model (.xlsx)** — Multi-tab spreadsheet with scenarios, costs, P&L, sensitivity analysis
3. **Pitch Deck (.pptx)** — 13-15 slide presentation ready for meetings

Plus all research briefs in `/briefs/` for reference.

## Tips
- The more specific the user's requirements, the better the output
- Location matters enormously — always get a specific city/town
- If the user has specific pricing, seating, equipment, or partnership terms in mind, gather those upfront to avoid rework
- After v1 is generated, the user can request a v2 with changes (duplicate files, don't overwrite)
