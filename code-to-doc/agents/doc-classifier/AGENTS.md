# Doc Classifier — Operating Instructions

## Purpose
Read scan results from change-scanner, classify each change using the
customer-facing skill rules, and hand off classified results to doc-publisher.

## Triggered By
Agent-to-agent message from change-scanner. Do NOT run on a schedule.

## Skills Used
- `customer-facing` — classification rules and category definitions

## Contract of Record
The canonical shared-file interface is defined in:
- `~/.openclaw/shared/data/contracts.md`

Treat that file as the source of truth for required fields, terminal statuses,
and overwrite behavior.

---

## Workflow

### 1. Validate input
Read `~/.openclaw/shared/data/scan-status.json`
- If missing → stop, log error
- If `status != "complete"` → stop, log "scan did not complete cleanly"
- If timestamp is older than 24h → stop, log "scan results are stale"
- Require `run_id`; if missing, stop and log error

Read `~/.openclaw/shared/data/scan-results.json`
- Require matching `run_id`
- Read PRs from `items`
- If missing or `items` is empty → stop, log "no scan results to classify"
- Ignore any request that does not match the current `run_id`

### 2. Apply heuristic pre-filter
Skip files already caught by change-scanner's filter.
Skip any file where patch is null or empty.

### 3. Classify each changed file using customer-facing skill rules

For each file in each PR, determine:
- Category: `BREAKING_CHANGE`, `NEW_FEATURE`, `BEHAVIOR_CHANGE`, `DEPRECATION`, or `INTERNAL`
- Confidence: 0.0 – 1.0
- Summary: one sentence explaining what changed from a customer perspective
- Doc suggestion: which doc file in docs/ should be updated (if not INTERNAL)

Apply confidence threshold rules from customer-facing skill:
- Confidence ≥ 0.7 → use classification
- Confidence 0.5–0.7 → downgrade to `INTERNAL`
- Confidence < 0.5 → `INTERNAL`, flag for human review

### 4. Aggregate per PR
Promote the highest-severity classification to the PR level:
`BREAKING_CHANGE > DEPRECATION > NEW_FEATURE > BEHAVIOR_CHANGE > INTERNAL`

A PR is customer-facing if ANY file (above confidence threshold) is non-INTERNAL.

### 5. Write output to shared/
Copy the input `run_id` into both output files and fully overwrite them.
Write outputs that conform to `~/.openclaw/shared/data/contracts.md`.

Write `~/.openclaw/shared/data/classified-results.json`:
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

Write `~/.openclaw/shared/data/classify-status.json`:
```json
{
  "run_id": "code-to-doc-2026-04-08T16:39:00Z",
  "status": "complete",
  "timestamp": "...",
  "prs_input": 5,
  "prs_customer_facing": 3,
  "prs_internal": 2,
  "flagged_for_review": 0
}
```
Always write classify-status.json, even on failure. On failure include the same `run_id` plus `error`.

### 6. Handoff decision
- If `prs_customer_facing > 0`:
  → Send agent-to-agent message to `doc-publisher` that includes:
  - the `run_id`
  - expected customer-facing PR count
  - instruction to ignore prior context, re-read shared files from disk, verify matching `run_id`, and fully overwrite publish status
- If `prs_customer_facing == 0`:
  → Stop. Log "All changes classified as INTERNAL" to memory.
- On failure:
  → Write failed status, log error, do NOT message doc-publisher.

---

## Memory Rules
Log each run to `memory/YYYY-MM-DD.md`:
- PRs received
- Classification breakdown (count per category)
- PRs passed to doc-publisher
- PRs flagged for human review
- Status
