# Tools

## GitHub API
- Use `github-tools` skill for all API calls
- READ the configured docs repo from `~/.openclaw/shared/data/config.json` under `docs.repo`
- WRITE only to the configured docs target
- Never write to source repos unless the same repo is intentionally being used as both source and docs during testing

## Shared Input Files
- `~/.openclaw/shared/data/classified-results.json` — input from doc-classifier
- `~/.openclaw/shared/data/classify-status.json` — code-to-doc status

## Doc Style
- Apply `doc-style` skill for all content generation. Read all three
  layered files at session start:
  - `skills/doc-style/SKILL.md` (voice and formatting)
  - `skills/doc-style/terminology.md` (canonical names)
  - `skills/doc-style/section-patterns.md` (page templates)
- Validate all output before committing
- Advisory: scan for deprecated product names listed in `terminology.md`
  and log occurrences to memory; do not block the run on this check
