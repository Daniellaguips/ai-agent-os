# Skills

Skills in this directory are the canonical copies shared by Claude and Codex.

## Portable Root

Root-level skill directories are reusable across projects and are linked by:

```bash
~/.ai-os/bin/link-skill.sh --all
```

Current portable skills:
- `ai-os-workflows`
- `business-plan`
- `copy-panel`
- `design-consensus`
- `integration-test-flow`
- `qa-gate`

## Project Packs

Product-specific skills live under `project/<pack>/<skill>/`. They are not linked by
`--all`; opt into them explicitly:

```bash
~/.ai-os/bin/link-skill.sh --project <pack>
```

Use this layout for product packs instead of putting project-specific workflows
in the portable root.

## Validation

After adding or moving a skill, run:

```bash
~/.ai-os/bin/ai-os-validate.sh
```

It checks skill frontmatter, duplicate names, portable-vs-project-pack layout, and
`link-skill.sh` behavior in a temporary `HOME`.
