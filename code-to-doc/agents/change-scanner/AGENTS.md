# Change Scanner — Operating Instructions

## Purpose
Fetch merged PRs from source repos since the last run, filter noise,
apply secret scanning, and hand clean diffs to doc-classifier.

## Skills Used
- `github-tools` — for all GitHub API calls and token minting

## Contract of Record
The canonical shared-file interface is defined in:
- `/data/openclaw/shared/data/contracts.md`

Treat that file as the source of truth for required fields, terminal statuses,
and overwrite behavior.

## Repo Configuration
Read code-to-doc metadata from `/data/openclaw/shared/data/config.json`.
Use `scanner.repos` as the source of truth.

Expected format:
```json
{
  "scanner": {
    "repos": [
      "trnt-ai/trent-openclaw-security-assessment"
    ],
    "defaultBranch": "main",
    "lookbackHours": 24
  },
  "docs": {
    "repo": "trnt-ai/trent-openclaw-security-assessment",
    "basePath": ".",
    "defaultBranch": "main"
  }
}
```

Each repo entry is `{owner}/{repo}`.
If `scanner.repos` is missing or empty, fail the run and write `scan-status.json` with `status: "failed"`.

---

## Workflow

### 1. Read last run state and compute effective lookback
Read `WORKING.md` for `last_run` timestamp.

Read `scanner.lookbackHours` from `/data/openclaw/shared/data/config.json`.

Compute:
- `lookback_since = now - scanner.lookbackHours`
- if `last_run` exists, `effective_since = earlier of (last_run, lookback_since)`
- if `last_run` is missing, `effective_since = lookback_since`

Use `effective_since` as the scan window start for this run.

### 2. Mint GitHub token
Use the `github-tools` skill. Mint fresh at the start of each run using:
- `GITHUB_APP_ID`
- `GITHUB_INSTALLATION_ID`
- `GITHUB_APP_PRIVATE_KEY_FILE`

Run the helper at `/data/openclaw/skills/github-tools/scripts/mint-token.js`, capture the installation token, and use it as `Bearer {installation_token}` for all GitHub REST API calls in this run.

### 3. Load repo list from code-to-doc config and fetch merged PRs since effective_since
For each configured entry in `scanner.repos`:
- Parse `{owner}/{repo}`
- Fetch:
```
GET /repos/{owner}/{repo}/pulls?state=closed&sort=updated&direction=desc&per_page=100
```
- Filter: `merged_at >= effective_since`

### 4. For each merged PR, fetch changed files
```
GET /repos/{owner}/{repo}/pulls/{pull_number}/files
```
Fields to capture: `filename`, `status`, `additions`, `deletions`, `patch`

### 5. Heuristic file filter — skip files matching any of:
```
tests/  test/  __tests__/  spec/
.github/  .circleci/  .gitlab-ci
__pycache__/  node_modules/  .next/
*.lock  *.pyc  package-lock.json  poetry.lock  yarn.lock
```
If ALL files in a PR are filtered, skip the PR entirely.

### 6. Secret scan — reject entire diff if it contains:
- `AKIA[0-9A-Z]{16}` (AWS key)
- `sk-[a-zA-Z0-9]{32,}`
- `-----BEGIN RSA PRIVATE KEY-----`
- `-----BEGIN PRIVATE KEY-----`
- `password\s*=\s*["'][^"']+["']`
- `.env` file contents
- Connection strings with credentials

If secrets found: log warning to memory, skip that PR, continue.

### 7. Write output to shared/
Every run must carry the `run_id` provided by Orchestrator. Copy it into both shared files.
Write outputs that conform to `/data/openclaw/shared/data/contracts.md`.

Write `/data/openclaw/shared/data/scan-results.json`:
```json
{
  "run_id": "code-to-doc-2026-04-08T16:39:00Z",
  "items": [
    {
      "repo": "trnt-ai/trent-openclaw-security-assessment",
      "pr_number": 42,
      "pr_title": "Add rate limiting to /analyze endpoint",
      "pr_body": "...",
      "merged_at": "2026-03-30T10:00:00Z",
      "merge_commit_sha": "abc123",
      "author": "devname",
      "changed_files": [
        {
          "filename": "api/routes/analyze.py",
          "status": "modified",
          "additions": 15,
          "deletions": 3,
          "patch": "..."
        }
      ]
    }
  ]
}
```

Write `/data/openclaw/shared/data/scan-status.json`:
```json
{
  "run_id": "code-to-doc-2026-04-08T16:39:00Z",
  "status": "complete",
  "scanned_by": "change-scanner",
  "timestamp": "2026-03-30T06:00:00Z",
  "effective_since": "2026-03-23T06:00:00Z",
  "last_run_read": "2026-03-30T06:00:00Z",
  "lookback_hours": 168,
  "repos": ["trnt-ai/trent-openclaw-security-assessment"],
  "prs_fetched": 10,
  "prs_after_filter": 5,
  "prs_rejected_secrets": 0
}
```
**Always write scan-status.json, even on failure.** On failure:
```json
{"run_id": "code-to-doc-2026-04-08T16:39:00Z", "status": "failed", "error": "...", "timestamp": "...", "effective_since": "...", "last_run_read": "...", "lookback_hours": 168}
```
Do not leave prior run output in place. Fully overwrite both files.

### 8. Update WORKING.md
Set `last_run` to current timestamp.

### 9. Handoff decision
- If `status == "complete"` AND `prs_after_filter > 0`:
  → Send agent-to-agent message to `doc-classifier` that includes:
  - the `run_id`
  - expected PR count
  - instruction to ignore prior context, re-read shared files from disk, and fully overwrite outputs
- If `status == "complete"` AND `prs_after_filter == 0`:
  → Stop. Log "No PRs with non-filtered changes found" to memory.
- If `status == "failed"`:
  → Stop. Log error to memory. Do NOT message doc-classifier.

---

## Memory Rules
Log each run to `memory/YYYY-MM-DD.md`:
- Repos checked
- PRs fetched per repo
- PRs after filter
- PRs rejected (secrets)
- Status
- Timestamp
