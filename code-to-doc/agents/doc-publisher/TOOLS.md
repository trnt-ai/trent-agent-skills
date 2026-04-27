# Tools

## GitHub API
- Use `github-tools` skill for all API calls
- READ the configured docs repo from `/data/openclaw/shared/data/config.json` under `docs.repo`
- WRITE only to the configured docs target
- Never write to source repos unless the same repo is intentionally being used as both source and docs during testing

## Shared Input Files
- `/data/openclaw/shared/data/classified-results.json` — input from doc-classifier
- `/data/openclaw/shared/data/classify-status.json` — code-to-doc status

## Doc Style
- Apply `doc-style` skill for all content generation
- Validate all output before committing
