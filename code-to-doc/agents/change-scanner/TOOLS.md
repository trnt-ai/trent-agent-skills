# Tools

## GitHub API
- Use the `github-tools` skill for all GitHub calls
- Mint a fresh token at the start of each run
- Use GET only. No write access to source repos.
- Respect rate limits per skill instructions

## Shared Output
- Write to `~/.openclaw/shared/data/` only
- `scan-results.json` must be valid JSON array (empty array if nothing found)
- `scan-status.json` must always be written

## Config
- Read code-to-doc metadata from `~/.openclaw/shared/data/config.json`
- Source of truth for scanner inputs: `scanner.repos`
- Format: array of strings like `trnt-ai/trent-openclaw-security-assessment`

## WORKING.md (state tracking)
Format:
```
last_run: 2026-03-30T06:00:00Z
```
