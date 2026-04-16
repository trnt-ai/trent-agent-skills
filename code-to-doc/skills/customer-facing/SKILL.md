---
name: customer-facing
description: Classification rules for determining if a code change is customer-facing
version: 1.0.0
user-invocable: false
---

# Customer-Facing Classification Rules

Apply these rules when deciding whether a code change should be documented
for customers. This file is the source of truth — edit it to tune the pipeline.

---

## Products in Scope

| Product | Repo | Surface |
|---------|------|---------|
| Threat Assessor | HumberAgent (backend) | REST API, assessment logic, report schemas |
| AppSec Advisor | HumberAgent (backend) | Chat API, advisor responses |
| Prompt Guard | HumberAgent (backend) | `/inference` API, analysis schema |
| Threat Dashboard | threat-dashboard (frontend) | UI behaviors visible to users |

---

## Change Categories

Classify every change into exactly one of these:

### `BREAKING_CHANGE` 🔴
Document immediately. Add migration note at top of relevant doc.
- Removed or renamed API endpoints
- Changed request/response field names or types
- Removed configuration options
- Changed authentication method or token format
- Removed features or capabilities
- Changed error response format or codes

### `NEW_FEATURE` 🟢
Document as new capability.
- New API endpoints
- New request parameters or response fields (additive)
- New configuration options
- New product capabilities or integrations
- New SDK methods

### `BEHAVIOR_CHANGE` 🟡
Document what changed and the impact.
- Changed default values
- Modified validation rules (stricter or looser)
- Changed rate limits
- Modified analysis logic that changes output
- Changed error messages customers see
- Changed scoring or severity thresholds

### `DEPRECATION` 🟠
Document with sunset timeline and migration path.
- Deprecated endpoints (still work but will be removed)
- Deprecated fields in request/response
- Deprecated SDK methods

### `INTERNAL` ⚪
**Skip. Do not document.**
- Refactoring with no API surface change
- Performance improvements with no behavioral change
- Internal variable/function renames
- Adding/modifying tests
- CI/CD configuration (`.github/`, `.circleci/`, etc.)
- Dependency updates with no breaking changes
- Log message changes
- Internal service calls not exposed to customers
- Database schema changes not reflected in API
- Code style / linting fixes
- Purely internal contributor guidance with no effect on customer setup, operation, or product behavior

---

## trnt-ai Specific Rules

### HumberAgent
- Routes under `/api/v*` → always evaluate for customer impact
- Routes under `/inference` → Prompt Guard API — always evaluate
- Changes to `schemas/`, `models/`, `serializers/` → check for API contract changes
- Changes to assessment scoring/logic → likely `BEHAVIOR_CHANGE`
- Changes to `internal/`, `utils/`, `helpers/` → likely `INTERNAL` unless they affect output

### threat-dashboard
- Changes to user-visible UI components → evaluate for `BEHAVIOR_CHANGE`
- Changes to dashboard data display logic → evaluate for `BEHAVIOR_CHANGE`
- Changes to `components/`, `pages/`, `views/` → check if user-visible
- Changes to `api/` client code → mirrors HumberAgent changes, avoid double-documenting
- Changes to `styles/`, `config/`, `__tests__/` → `INTERNAL`

---

## Documentation and Instruction Changes

Do not automatically treat docs-only changes as internal.
Classify instruction or documentation changes as customer-facing when they change how a customer installs, configures, authenticates with, operates, or interprets the product.

Examples that should usually be customer-facing:
- Setup or onboarding instruction changes customers must follow
- API key, credential, auth, or environment configuration guidance changes
- Deployment or runtime configuration steps that affect customer success
- Usage instructions that materially change expected behavior or outcomes
- Troubleshooting guidance added because product behavior or required steps changed

Examples that are still internal:
- Contributor workflow docs
- Internal architecture notes
- Repo maintenance guidance
- Style, wording, or screenshot refreshes with no operational impact

README.md is not an automatic skip. Evaluate it based on audience and operational impact.

## Filter: Skip These Files Always

Even if changed, never classify these as customer-facing:
```
tests/
test/
__tests__/
spec/
.github/
.circleci/
.gitlab-ci*
__pycache__/
node_modules/
.next/
*.lock
*.pyc
package-lock.json
poetry.lock
yarn.lock
.env*
Makefile
Dockerfile (unless it changes a port or ENV that affects API)
CHANGELOG.md (internal)
```

---

## Security: Secret Detection

If a diff contains any of the following patterns, **reject the entire diff**
(log a warning, skip it, do NOT classify or document):
- `AKIA[0-9A-Z]{16}` (AWS Access Key)
- `sk-[a-zA-Z0-9]{32,}` (API keys)
- `-----BEGIN RSA PRIVATE KEY-----`
- `-----BEGIN PRIVATE KEY-----`
- `password\s*=\s*["'][^"']+["']`
- `.env` file contents in diff
- Connection strings with credentials (`postgresql://user:pass@`)

---

## Confidence Threshold

When classifying with LLM:
- Confidence ≥ 0.7 → use that classification
- Confidence 0.5–0.7 → downgrade to `INTERNAL` (safe default)
- Confidence < 0.5 → mark as `INTERNAL` and log for human review

When in doubt, document too little rather than too much.
False positives (documenting internal changes) are worse than false negatives.
