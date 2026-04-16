# OpenClaw Code-to-Doc Install Guide

This code-to-doc system should be installable on another OpenClaw deployment with a short guided setup, not a long manual checklist.

## Install goal

Set up the code-to-doc system on a fresh OpenClaw deployment by collecting a small set of required details, writing the needed config, and validating prerequisites before first run.

## Recommended install experience

Use a guided installer that asks for values in phases and validates each phase before continuing.

### Phase 1: Confirm code-to-doc install

Ask:
- Do you want to install the code-to-doc system on this OpenClaw deployment?
- Do you want the default 4-agent code-to-doc setup?
  - `orchestrator`
  - `change-scanner`
  - `doc-classifier`
  - `doc-publisher`

If yes, continue.

### Phase 2: GitHub authentication

Ask:
- GitHub App ID
- GitHub Installation ID
- Path to GitHub App private key PEM, or whether the installer should create the standard credentials path and tell the user where to place it

Validate:
- required values are present
- PEM path exists if user says it already exists
- permissions expectation is understood:
  - pull requests: read
  - contents: read/write

### Phase 3: Source and docs repos

Ask:
- Which source repos should be scanned?
  - one or more `{owner}/{repo}` values
- What is the docs target repo?
- What docs base path should be updated?
- What is the default branch?
- What lookback window should be used for the initial scan?

Provide defaults:
- docs base path: `.`
- default branch: `main`
- lookback hours: `168`

Validate:
- repo strings match `{owner}/{repo}`
- at least one source repo is provided
- docs repo is provided
- lookback hours is numeric

### Phase 4: Workspace and shared state

Ask:
- Use standard OpenClaw paths for shared state and credentials?

Recommended default:
- yes

Expected paths:
- shared: `~/.openclaw/shared/data/`
- credentials: `~/.openclaw/credentials/`
- orchestrator workspace: `~/.openclaw/agents/orchestrator`

### Phase 5: Agent install

Install or update:
- `~/.openclaw/agents/orchestrator/`
- `~/.openclaw/agents/change-scanner/`
- `~/.openclaw/agents/doc-classifier/`
- `~/.openclaw/agents/doc-publisher/`
- shared contract doc
- code-to-doc config
- required skills or skill references

Validate:
- all agent files exist
- `shared/data/config.json` exists
- `shared/data/contracts.md` exists

### Phase 6: Dry-run validation

Check:
- OpenClaw can read the config
- required files exist
- GitHub auth can mint a token
- configured repos are reachable
- docs target repo is reachable

Do not run publishing during install.

### Phase 7: First run option

Ask:
- Do you want to run the full code-to-doc system now?
- Or stop after validation?

## Installer design principles

- Ask only for values that vary by deployment
- Provide sensible defaults for everything else
- Validate before writing final config when possible
- Show a summary before applying changes
- Keep install idempotent so it can be re-run safely
- Prefer standard OpenClaw paths over custom ones unless the user explicitly overrides them

## Suggested output artifacts

The installer should produce or update:
- `shared/data/config.json`
- agent instruction files
- `shared/data/contracts.md`
- a short local install state note with timestamp and chosen values

## Suggested interactive summary before apply

Show:
- source repos
- docs target repo
- docs base path
- default branch
- lookback hours
- GitHub App ID
- GitHub Installation ID
- PEM path
- whether first run will happen now

Then ask for a final confirmation before writing.

## What should stay configurable later

After install, users should only need to edit:
- `shared/data/config.json`
- policy skills like classification or doc style

They should not need to rewrite agent instructions for normal repo changes.
