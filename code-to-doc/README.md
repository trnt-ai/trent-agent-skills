# code-to-doc

Automated pipeline that turns merged PRs into customer-facing documentation. Designed for [OpenClaw](https://github.com/trnt-ai) deployments.

## How it works

Four agents run in sequence, communicating via shared JSON files:

```
Orchestrator → Change Scanner → Doc Classifier → Doc Publisher
```

1. **Change Scanner** fetches merged PRs from configured repos, filters noise, scans for secrets
2. **Doc Classifier** classifies each change (breaking change, new feature, behavior change, deprecation, or internal)
3. **Doc Publisher** reads existing docs, generates updates following your doc style, and opens a PR for review

The pipeline stops early if there are no customer-facing changes. Doc Publisher never pushes directly to main — it always creates a PR.

## Requirements

- An [OpenClaw](https://github.com/trnt-ai) deployment
- Node.js (for GitHub App token minting)
- Python 3 (for the doc publisher helper)
- A GitHub App with `pull_requests:read` and `contents:read+write` permissions

## Install

```bash
git clone https://github.com/trnt-ai/trent-agent-skills.git
cd trent-agent-skills/code-to-doc
bash installer/install.sh
```

The installer:

1. Syncs agent files, skills, and shared contracts into `~/.openclaw/`
2. Creates `config.json` from template if missing
3. Creates `WORKING.md` for stateful agents if missing
4. Registers all 4 agents in `openclaw.json` (upsert — won't remove your other agents)
5. Adds agents to the agent-to-agent handoff allowlist
6. Validates all required files are in place
7. Restarts the OpenClaw gateway

Safe to re-run after pulling updates — it syncs code files but never overwrites runtime state (`memory/`, `WORKING.md`, `config.json`, pipeline status files).

## Configuration

After install, edit `~/.openclaw/shared/data/config.json` with your repos:

```json
{
  "scanner": {
    "repos": ["owner/source-repo"],
    "defaultBranch": "main",
    "lookbackHours": 168
  },
  "docs": {
    "repo": "owner/docs-repo",
    "basePath": ".",
    "defaultBranch": "main"
  }
}
```

No need to re-run the installer for config-only changes.

The installer also registers agents in `~/.openclaw/openclaw.json`:

```json
{
  "agents": {
    "list": [
      { "id": "orchestrator", "workspace": "~/.openclaw/agents/orchestrator" },
      { "id": "change-scanner", "workspace": "~/.openclaw/agents/change-scanner" },
      { "id": "doc-classifier", "workspace": "~/.openclaw/agents/doc-classifier" },
      { "id": "doc-publisher", "workspace": "~/.openclaw/agents/doc-publisher" }
    ]
  },
  "tools": {
    "agentToAgent": {
      "enabled": true,
      "allow": ["orchestrator", "change-scanner", "doc-classifier", "doc-publisher"]
    }
  }
}
```

## Customization

Policy is defined in skill files, not hardcoded:

- `skills/customer-facing/SKILL.md` — classification rules, confidence thresholds, skip patterns
- `skills/doc-style/SKILL.md` — tone, structure, heading conventions, templates per change category

Edit these to match your product's documentation standards.

## Project structure

```
code-to-doc/
  agents/
    orchestrator/       — triggers runs, verifies each stage
    change-scanner/     — fetches merged PRs, filters, scans for secrets
    doc-classifier/     — classifies changes by customer impact
    doc-publisher/      — generates docs, opens PR on docs repo
  skills/
    github-tools/       — token minting, GitHub REST API conventions
    customer-facing/    — classification rules and thresholds
    doc-style/          — documentation tone, structure, templates
  shared/data/
    contracts.md        — JSON schemas for inter-agent communication
    config.example.json — template for runtime config
  installer/
    install.sh          — setup script (sync, register, validate)
    install.md          — install design spec
    installer-questionnaire.json — structured config schema
```

## Environment variables

Set these before running the pipeline:

| Variable | Description |
|----------|-------------|
| `GITHUB_APP_ID` | GitHub App ID |
| `GITHUB_INSTALLATION_ID` | GitHub App Installation ID |
| `GITHUB_APP_PRIVATE_KEY_FILE` | Path to PEM file |
| `OPENCLAW_ROOT` | OpenClaw home directory (default: `~/.openclaw`) |
| `OPENCLAW_DATA_DIR` | Shared data directory (default: `~/.openclaw/shared/data/`) |
