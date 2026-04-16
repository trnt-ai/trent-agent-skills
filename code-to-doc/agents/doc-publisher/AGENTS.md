# Doc Publisher — Operating Instructions

## Purpose
Read classified changes, generate updated customer documentation following
trnt-ai's doc style, and open a PR on the configured docs repository for human review.

## Triggered By
Agent-to-agent message from doc-classifier. Do NOT run on a schedule.

## Skills Used
- `github-tools` — for all GitHub API calls (read existing docs + create PR)
- `doc-style` — tone, structure, formatting rules for all generated content

## Contract of Record
The canonical shared-file interface is defined in:
- `~/.openclaw/shared/data/contracts.md`

Treat that file as the source of truth for required fields, terminal statuses,
and overwrite behavior.

---

## Workflow

### 1. Validate input
Read `~/.openclaw/shared/data/classify-status.json`
- If missing, status != "complete", or timestamp > 24h old → stop, log error
- Require `run_id`; if missing, stop and log error

Read `~/.openclaw/shared/data/classified-results.json`
- Require matching `run_id`
- Read PRs from `items`
- Filter to only `customer_facing: true` entries
- If none remain → stop, log "no customer-facing changes to document"
- Ignore any request that does not match the current `run_id`

Read `~/.openclaw/shared/data/config.json`
- Use `docs.repo` as the target docs repository
- Use `docs.basePath` as the documentation root path
- Use `docs.defaultBranch` if present, otherwise `main`
- If `docs.repo` is missing, stop and log error

Do not assume a fixed destination repo. Always defer to `shared/data/config.json`
for repository, path root, and branch.

### 2. Mint GitHub token
Use the `github-tools` skill with:
- `GITHUB_APP_ID`
- `GITHUB_INSTALLATION_ID`
- `GITHUB_APP_PRIVATE_KEY_FILE`

Run the helper at `~/.openclaw/skills/github-tools/scripts/mint-token.js`, capture the installation token, and use it as `Bearer {installation_token}` for all GitHub REST API calls in this run.

### 3. Read existing docs from configured docs repo
For each `doc_suggestion` path in classified-results:
```
GET /repos/{docs.repo}/contents/{doc_suggestion}?ref={docs.defaultBranch}
```
Decode base64 content. Store current SHA (needed for update commit).

Also fetch the docs root listing for context:
```
GET /repos/{docs.repo}/contents/{docs.basePath}?ref={docs.defaultBranch}
```

### 4. Generate updated documentation

Apply `doc-style` skill rules strictly.

For each customer-facing PR (grouped by category, highest severity first):

**BREAKING_CHANGE:**
- Add migration notice at top of relevant doc section
- Use the breaking change template from doc-style skill
- This is highest priority — always appears first

**NEW_FEATURE:**
- Add new section under appropriate product heading
- Follow new feature template from doc-style skill

**BEHAVIOR_CHANGE:**
- Update existing section in place if heading matches
- Use behavior change template

**DEPRECATION:**
- Add deprecation notice with sunset date placeholder
- Use deprecation template

Never:
- Include raw diffs or code from source repos
- Include internal file paths
- Include author names or PR numbers in prose (put them only in PR body metadata)
- Include anything that looks like a credential

### 5. Validate generated output
Check each generated doc:
- Valid markdown (no unclosed code blocks, no raw HTML)
- No patterns matching secrets (reuse secret scan patterns from customer-facing skill)
- No internal paths or credentials
- Each section references an actual classified change
- Passes doc-style rules (heading levels, no marketing language)

If validation fails: log error, stop, do NOT create PR.

### 6. Create PR on configured docs repo

Build a manifest JSON file and pass it to the helper script. The helper handles
branch creation, multi-file commits, and PR creation in one invocation.

**Step A — Write each generated doc to a temp file** (one file per doc_suggestion path).

**Step B — Write the PR body markdown to a temp file.**

**Step C — Build the manifest:**
```json
{
  "token": "{installation_token}",
  "repo": "{docs.repo}",
  "base": "{docs.defaultBranch}",
  "branch": "doc-agent/update-YYYY-MM-DD",
  "pr_title": "docs: auto-update from recent changes ({date})",
  "pr_body_file": "/tmp/pr-body.md",
  "run_id": "{run_id}",
  "files": [
    {"path": "docs/products/foo/quickstart.md", "content_file": "/tmp/foo.md"},
    {"path": "docs/products/bar/overview.md",   "content_file": "/tmp/bar.md"}
  ]
}
```

**Step D — Run the helper:**
```
python publish_docs_pr.py manifest.json
```

The helper will:
- Create the branch (tolerates 422 if it already exists)
- For each file: fetch existing SHA if present, then commit (update or create)
- Open the PR with the provided title and body
- Write `publish-status.json` with `paths` array listing all committed files
- Retry on 429 / rate-limit 403 (up to 3 attempts with backoff)

Status is written to `$OPENCLAW_DATA_DIR/publish-status.json`
(defaults to `~/.openclaw/shared/data/`).

**PR body format:**
```markdown
## Automated Documentation Update

Generated by doc-publisher from merged PRs in configured source repos.
**Review carefully before merging.**

---

## Changes Summary

| Product | PR | Category | Summary |
|---------|-----|----------|---------|
| Product | trent-openclaw-security-assessment#42 | BEHAVIOR_CHANGE | Example customer-visible behavior change |

---

## Source PRs

- [trent-openclaw-security-assessment#42](https://github.com/trnt-ai/trent-openclaw-security-assessment/pull/42) — {pr_title}

---

*Generated: {timestamp} | code-to-doc run: change-scanner → doc-classifier → doc-publisher*
```

### 7. Write publish status, notify, and log
Always write `~/.openclaw/shared/data/publish-status.json`, even on failure.

Use only terminal statuses defined by the shared contract:
- `complete`
- `failed`

On success, write:
```json
{
  "run_id": "code-to-doc-2026-04-08T16:39:00Z",
  "status": "complete",
  "timestamp": "2026-04-08T16:33:00Z",
  "repo": "trnt-ai/trent-openclaw-security-assessment",
  "branch": "doc-agent/update-2026-04-08",
  "paths": [
    "docs/products/openclaw-security-assessment/quickstart.md",
    "docs/products/openclaw-security-assessment/api-reference.md"
  ],
  "pr_url": "https://github.com/trnt-ai/trent-openclaw-security-assessment/pull/16",
  "commit_sha": "..."
}
```

On failure, write:
```json
{
  "run_id": "code-to-doc-2026-04-08T16:39:00Z",
  "status": "failed",
  "timestamp": "2026-04-08T16:20:00Z",
  "step": "commit_file",
  "failed_path": "docs/products/openclaw-security-assessment/quickstart.md",
  "repo": "trnt-ai/trent-openclaw-security-assessment",
  "branch": "doc-agent/update-2026-04-08",
  "paths": ["docs/products/openclaw-security-assessment/quickstart.md"],
  "result": {"...": "..."}
}
```
You may include additional metadata fields, but do not replace or rename the
canonical fields from `shared/data/contracts.md`.

Do not leave prior publish output in place. Fully overwrite the status file.

After PR is created:
- Send message back to main OpenClaw session (or configured channel):
  `"📝 Doc PR created: {pr_url} — {change_count} changes ({categories})"`
- Log to `memory/YYYY-MM-DD.md`:
  - PRs processed
  - Docs updated (filenames)
  - PR URL
  - Any skipped changes and why

---

## Memory Rules
Log each run:
- Changes received, categories breakdown
- Docs files updated
- PR URL
- Validation failures (if any)
- Skipped changes
