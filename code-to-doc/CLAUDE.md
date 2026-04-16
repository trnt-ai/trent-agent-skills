# CLAUDE.md — code-to-doc

## What This Is

A multi-agent pipeline that turns merged PRs into customer-facing documentation. Four agents communicate via shared JSON contract files — not chat, not RPC.

**Pipeline:** Orchestrator -> Change Scanner -> Doc Classifier -> Doc Publisher

Each agent writes a status file and a results file. The next agent reads them, verifies `run_id` and `status: "complete"`, then proceeds. The orchestrator verifies the whole chain.

## Architecture

```
agents/
  orchestrator/      — triggers runs, verifies each stage via contract files
  change-scanner/    — fetches merged PRs, filters noise, scans for secrets
  doc-classifier/    — classifies changes (BREAKING_CHANGE, NEW_FEATURE, etc.)
  doc-publisher/     — generates docs, opens PR on docs repo

skills/
  github-tools/      — token minting, REST API conventions, rate limits
  customer-facing/   — classification rules per product, confidence thresholds
  doc-style/         — trnt-ai doc tone, structure, templates

shared/data/
  contracts.md       — canonical JSON schemas for all inter-agent files

installer/
  install.md         — 7-phase guided setup
  installer-questionnaire.json — structured config questionnaire
```

## Principles

### Think Before Coding
- Read the agent's full file set (SOUL.md, AGENTS.md, TOOLS.md, contracts.md) before modifying it.
- Understand how the agent fits in the pipeline before changing its behavior.
- Contract changes ripple — check upstream and downstream agents before altering a schema.

### Simplicity First
- Agents are stateless per session. They read files from disk, do their job, write output. Don't add state management.
- Skills are instruction documents, not code libraries. Keep them declarative.
- Three agents reading the same contract is simpler than a message bus.

### Surgical Changes
- Agent files (IDENTITY.md, SOUL.md, AGENTS.md, etc.) are tightly scoped. Edit only the file that owns the concern.
- Don't "improve" an agent's personality when fixing its classification logic.
- Contract changes require updating contracts.md AND every agent that reads/writes the affected file.

### Goal-Driven Execution
- The pipeline exists to produce one thing: a PR on the docs repo. Work backward from that.
- If a stage has no customer-facing changes, the pipeline stops early. That's correct behavior, not a failure.
- False positives (over-documenting) are worse than false negatives. When uncertain, classify as INTERNAL.

## Key Conventions

### Agent File Structure
Every agent has these files (read in this order at session startup):
1. `SOUL.md` — identity and boundaries
2. `USER.md` — who the deployment operator is
3. `WORKING.md` — mutable session state (last_run, status)
4. `memory/YYYY-MM-DD.md` — daily logs
5. `AGENTS.md` — full behavioral instructions

Supporting files: `IDENTITY.md` (name/emoji), `HEARTBEAT.md` (periodic tasks), `TOOLS.md` (local setup notes).

### Skills
`skills/{name}/SKILL.md` — self-contained instruction document. Optional `scripts/` directory for helpers.

### Shared Contracts
All inter-agent data flows through `~/.openclaw/shared/data/` as JSON files:
- `scan-status.json`, `scan-results.json` (written by change-scanner)
- `classify-status.json`, `classified-results.json` (written by doc-classifier)
- `publish-status.json` (written by doc-publisher)

**Rules:** Every file includes `run_id`. Writers fully overwrite (no append). Status is always terminal: `complete` or `failed`. Readers reject mismatched `run_id`s.

### Languages
- **Markdown** — agent instructions, skills, contracts (primary)
- **Python** — helper scripts (doc-publisher's `publish_docs_pr.py`)
- **JavaScript/Node.js** — GitHub token minting (`skills/github-tools/scripts/mint-token.js`)
- **JSON** — config, contracts, pipeline outputs

### Config
Runtime config lives at `~/.openclaw/shared/data/config.json`. Requires env vars: `GITHUB_APP_ID`, `GITHUB_INSTALLATION_ID`, `GITHUB_APP_PRIVATE_KEY_FILE`.

## Security

- Change-scanner rejects diffs containing secrets (AWS keys, API keys, private keys, passwords, connection strings, `.env` contents). Entire diff is skipped.
- No credentials, internal paths, or raw diffs in generated documentation.
- Change-scanner and doc-classifier are read-only. Doc-publisher writes only to the docs repo, never source repos.
- Doc-publisher creates PRs — never pushes directly to main.

## Build / Test / Run

No build system. No test runner yet. Agents run via Claude AI Agent SDK. The installer (`installer/install.md`) handles first-time setup with dry-run validation.
