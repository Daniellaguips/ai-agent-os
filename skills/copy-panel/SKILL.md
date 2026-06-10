---
name: copy-panel
description: Run a panel of independent copy raters that score a page/email/screen's copy on configurable dimensions such as conversion, fluency, pleasantness, and skimmability. Use when asked to rate copy, score a page's copy, run a copy review/panel, or improve marketing/landing/email copy. Reusable across projects; reads the project's brand canon if one exists.
---

# copy-panel

Multi-rater copy review for pages, emails, product screens, and scripts. The point is
to de-correlate taste: run several independent passes, then aggregate only the
patterns that survive more than one rater.

## Before running
1. If the project has a brand canon (`docs/brand/BRAND-CANON.md`, `BRAND.md`, or
   equivalent), read it first and pass only public-safe positioning and voice into
   every rater prompt. Never put confidential numbers or sensitive customer facts into
   suggested public copy.
2. Identify the exact copy under review: live URL, screenshot, source file, email
   preview, or pasted text. Extract the visible copy so every rater reviews the same
   text.

## Workflow

Run at least 3 independent raters. If multi-agent tooling is available, spawn them;
otherwise do separate passes yourself with distinct lenses:
- target customer / user
- conversion copywriter
- first-glance skimmer

Each rater returns:
- scores from 1-10 for every requested dimension
- one-line note per dimension
- overall score
- 3-6 concrete edits in the form: current text -> replacement -> why

Default dimensions: conversion, fluency, pleasantness, skimmability. Override per
brief when another dimension matters, such as clarity, compliance, trust, or
brand-voice fit.

## Output

Report per-dimension averages, the overall score, issues raised by at least two
raters, and a deduped prioritized edit list. If the user asked for edits, apply the
high-confidence replacements and call out any copy decision that needs product or
legal judgment.
