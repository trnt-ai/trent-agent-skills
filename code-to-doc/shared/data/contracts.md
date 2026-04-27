# Pipeline JSON Contracts

This file freezes the canonical shared-file interface for the code-to-doc system.
All stages must read and write these files exactly as the contract of record.

## Global rules

- Shared directory: `/data/openclaw/shared/data/`
- Contract files:
  - `scan-status.json`
  - `scan-results.json`
  - `classify-status.json`
  - `classified-results.json`
  - `publish-status.json`
- Every file must include the same `run_id` for a given code-to-doc run.
- Writers must fully overwrite their contract files. Do not append. Do not partially merge.
- Readers must treat the JSON files as source of truth, not agent chat replies.
- Unknown additional fields are allowed, but canonical fields must not be removed, renamed, or type-changed.
- Terminal stage status values are:
  - `complete`
  - `failed`
- A stage that encounters an error must still write its status file with `status: "failed"`.

## File 1: `scan-status.json`

Written by: `change-scanner`

Required shape:

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

Required fields:
- `run_id` string
- `status` string, one of `complete` or `failed`
- `timestamp` ISO-8601 string

Expected on success:
- `scanned_by` string
- `effective_since` ISO-8601 string
- `last_run_read` ISO-8601 string or null if unavailable
- `lookback_hours` number
- `repos` array of `{owner}/{repo}` strings
- `prs_fetched` number
- `prs_after_filter` number
- `prs_rejected_secrets` number

Expected on failure:
- preserve `run_id`
- set `status` to `failed`
- include `error` string
- include `timestamp`
- include any known context fields such as `effective_since`, `last_run_read`, `lookback_hours`

## File 2: `scan-results.json`

Written by: `change-scanner`

Required shape:

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

Required fields:
- `run_id` string
- `items` array

Per item required fields:
- `repo` string
- `pr_number` number
- `pr_title` string
- `merged_at` ISO-8601 string
- `changed_files` array

Per changed file required fields:
- `filename` string
- `status` string
- `additions` number
- `deletions` number
- `patch` string or null

Optional but recommended:
- `pr_body`
- `merge_commit_sha`
- `author`

## File 3: `classify-status.json`

Written by: `doc-classifier`

Required shape:

```json
{
  "run_id": "code-to-doc-2026-04-08T16:39:00Z",
  "status": "complete",
  "timestamp": "2026-03-30T06:10:00Z",
  "prs_input": 5,
  "prs_customer_facing": 3,
  "prs_internal": 2,
  "flagged_for_review": 0
}
```

Required fields:
- `run_id` string
- `status` string, one of `complete` or `failed`
- `timestamp` ISO-8601 string

Expected on success:
- `prs_input` number
- `prs_customer_facing` number
- `prs_internal` number
- `flagged_for_review` number

Expected on failure:
- preserve `run_id`
- set `status` to `failed`
- include `error` string
- include `timestamp`

## File 4: `classified-results.json`

Written by: `doc-classifier`

Required shape:

```json
{
  "run_id": "code-to-doc-2026-04-08T16:39:00Z",
  "items": [
    {
      "repo": "trnt-ai/trent-openclaw-security-assessment",
      "pr_number": 42,
      "pr_title": "Add rate limiting to /analyze endpoint",
      "merged_at": "2026-03-30T10:00:00Z",
      "pr_classification": "BEHAVIOR_CHANGE",
      "customer_facing": true,
      "files": [
        {
          "filename": "api/routes/analyze.py",
          "classification": "BEHAVIOR_CHANGE",
          "confidence": 0.85,
          "summary": "Rate limiting added to the /analyze endpoint; requests exceeding the limit now return HTTP 429.",
          "doc_suggestion": "docs/products/threat-assessor/quickstart.md"
        }
      ]
    }
  ]
}
```

Required fields:
- `run_id` string
- `items` array

Per item required fields:
- `repo` string
- `pr_number` number
- `pr_title` string
- `merged_at` ISO-8601 string
- `pr_classification` string
- `customer_facing` boolean
- `files` array

Per file required fields:
- `filename` string
- `classification` string
- `confidence` number
- `summary` string
- `doc_suggestion` string or null

Allowed classification values:
- `BREAKING_CHANGE`
- `NEW_FEATURE`
- `BEHAVIOR_CHANGE`
- `DEPRECATION`
- `INTERNAL`

## File 5: `publish-status.json`

Written by: `doc-publisher`

This is the final stage status file. It is a status contract, not a staging area.
Do not use non-terminal values such as `ready` here.

Required success shape:

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
  "commit_sha": "abc123"
}
```

Required failure shape:

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
  "result": {"message": "GitHub API error"}
}
```

Required fields:
- `run_id` string
- `status` string, one of `complete` or `failed`
- `timestamp` ISO-8601 string

Expected on success:
- `repo` string, must match configured `docs.repo`
- `branch` string
- at least one of:
  - `path` string
  - `paths` array of strings
- `pr_url` string
- `commit_sha` string

Expected on failure:
- `step` string
- `repo` string if known
- `branch` string if known
- `path` or `paths` if known
- `result` object and/or `error` string

## Validation rules for all readers

- Reject files with missing `run_id`.
- Reject downstream input when `run_id` does not match the expected current run.
- Treat missing required canonical fields as contract failure.
- Treat non-terminal statuses other than `complete` or `failed` as invalid for status files.
- Prefer failing loudly over silently continuing on malformed contract data.

## Change control

If this contract changes:
- update this file first
- then update agent instructions and implementations
- keep changes backward-compatible when possible
- if a breaking contract change is unavoidable, bump the version in this document and migrate all stages together
